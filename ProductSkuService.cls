public class ProductSkuService {

    /*
     * Esterah Product & SKU Design
     *
     * Final Variant SKU format:
     *   P DDDD MM SSS
     *
     * No separators.
     *
     * Segments:
     *   P    = Product Type Code
     *   DDDD = Design / Style Number, zero-padded 4 digits
     *   MM   = Material Code
     *   SSS  = Size / Dimension Code, zero-padded 3 digits
     *
     * Full Variant SKU examples:
     *   R0042GP075 = Ring, design 0042, Gold Plated, size 7.5
     *   R0042GP070 = Ring, design 0042, Gold Plated, size 7
     *   R0042SP070 = Ring, design 0042, Silver Plated, size 7
     *   N0043GP000 = Necklace, design 0043, Gold Plated, no size
     *   A0045NA000 = Accessory, design 0045, no material, no size
     *   G0047NA000 = Gift Voucher, design 0047, no material, no size
     *
     * Parent Product SKU:
     *   Existing Product2.StockKeepingUnit field stores the shortened SKU:
     *   P + DDDD
     *
     * Parent SKU examples:
     *   R0042
     *   N0043
     *   A0045
     *   G0047
     *
     * Variant Product SKU:
     *   Existing Product2.StockKeepingUnit field stores the full SKU:
     *   P + DDDD + MM + SSS
     *
     * Product Type sequence rule:
     *   Each product type has its own independent style/design sequence.
     *
     *   Rings:         R0001, R0002, R0003
     *   Necklaces:     N0001, N0002, N0003
     *   Bracelets:     B0001, B0002, B0003
     *   Earrings:      E0001, E0002, E0003
     *   Accessories:   A0001, A0002, A0003
     *   Gift Vouchers: G0001, G0002, G0003
     *   Sets:          S0001, S0002, S0003
     *
     * Important:
     *   Parent Product SKU is the source of truth when it already exists.
     *   All child variants under the same parent must reuse the parent style number.
     *
     * Example:
     *   Parent Product SKU = R0026
     *
     *   Child variants:
     *     R0026SG050
     *     R0026SG055
     *     R0026SG065
     *     R0026SG070
     *     R0026SG080
     *     R0026SG090
     */

    private static final Integer MAX_STYLE_SCAN_ATTEMPTS = 9999;

    private static final Set<String> VALID_TYPE_CODES = new Set<String>{
        'R', 'N', 'B', 'E', 'A', 'G', 'S'
    };

    private static final Map<String, Schema.SObjectField> PRODUCT2_FIELD_MAP =
        Product2.SObjectType.getDescribe().fields.getMap();

    public class ProductSkuException extends Exception {}

    public static void assignSkusForNewInboundVariants(List<Product2> variants) {
        if (variants == null || variants.isEmpty()) {
            return;
        }

        Map<String, Set<Integer>> usedStyleNumbersByTypeCode =
            getUsedStyleNumbersByTypeCode();

        Set<String> usedSkus = getUsedSkus();

        Map<String, Integer> styleNumberByStyleKey =
            new Map<String, Integer>();

        for (Product2 variant : variants) {
            if (!shouldGenerateSku(variant)) {
                continue;
            }

            String typeCode = getTypeCode(variant);
            String materialCode = getMaterialCode(variant, typeCode);
            String dimensionCode = getDimensionCode(variant);

            if (String.isBlank(typeCode)) {
                System.debug(
                    LoggingLevel.WARN,
                    'ProductSkuService.assignSkusForNewInboundVariants: Cannot generate SKU. ' +
                    'Product type/family is not mapped. Shop_ID__c=' +
                    getStringField(variant, 'Shop_ID__c')
                );
                continue;
            }

            if (String.isBlank(materialCode)) {
                System.debug(
                    LoggingLevel.WARN,
                    'ProductSkuService.assignSkusForNewInboundVariants: Cannot generate SKU. ' +
                    'Material is not mapped. Shop_ID__c=' +
                    getStringField(variant, 'Shop_ID__c')
                );
                continue;
            }

            if (String.isBlank(dimensionCode)) {
                dimensionCode = '000';
            }

            String styleKey = buildStyleKey(variant, typeCode);

            Integer assignedStyleNumber;

            if (styleNumberByStyleKey.containsKey(styleKey)) {
                assignedStyleNumber = styleNumberByStyleKey.get(styleKey);
            } else {
                assignedStyleNumber =
                    findExistingStyleNumberForVariant(variant, typeCode);

                Set<Integer> usedStyleNumbersForType =
                    getUsedStyleNumbersForType(
                        usedStyleNumbersByTypeCode,
                        typeCode
                    );

                if (assignedStyleNumber == null) {
                    assignedStyleNumber =
                        findNextFreeStyleNumber(usedStyleNumbersForType, 1);
                }

                if (assignedStyleNumber == null) {
                    throw new ProductSkuException(
                        'Unable to generate unique SKU style number for product type ' +
                        typeCode +
                        ' after scanning ' +
                        MAX_STYLE_SCAN_ATTEMPTS +
                        ' candidates.'
                    );
                }

                styleNumberByStyleKey.put(styleKey, assignedStyleNumber);
                usedStyleNumbersForType.add(assignedStyleNumber);
            }

            String styleCode = formatNumber(assignedStyleNumber, 4);
            String sku = buildSku(
                typeCode,
                materialCode,
                styleCode,
                dimensionCode
            );

            /*
             * Do not allocate a new design/style number to hide a duplicate.
             * If the same parent/design + material + size already exists,
             * that is a real product-data issue.
             */
            if (usedSkus.contains(sku)) {
                throw new ProductSkuException(
                    'Duplicate SKU generated: ' +
                    sku +
                    '. This means the same design/material/size combination already exists. ' +
                    'Shop_ID__c=' +
                    getStringField(variant, 'Shop_ID__c')
                );
            }

            variant.StockKeepingUnit = sku;

            setFieldIfPresent(variant, 'Style_Number__c', styleCode);
            setFieldIfPresent(variant, 'SKU_Style_Number__c', styleCode);
            setFieldIfPresent(variant, 'Dimension_Code__c', dimensionCode);

            usedSkus.add(sku);

            System.debug(
                LoggingLevel.INFO,
                'ProductSkuService.assignSkusForNewInboundVariants: Assigned SKU "' +
                sku +
                '" to variant Shop_ID__c=' +
                getStringField(variant, 'Shop_ID__c') +
                ', Size__c=' +
                getStringField(variant, 'Size__c')
            );
        }
    }

    public static List<Product2> resolveSkuCollisions(
        List<Product2> variants,
        Database.UpsertResult[] variantResults
    ) {
        List<Product2> toRetry = new List<Product2>();

        if (variants == null || variants.isEmpty()) {
            return toRetry;
        }

        if (variantResults == null || variantResults.isEmpty()) {
            return toRetry;
        }

        Integer maxSize = Math.min(variants.size(), variantResults.size());

        for (Integer i = 0; i < maxSize; i++) {
            Database.UpsertResult result = variantResults[i];

            if (result == null || result.isSuccess()) {
                continue;
            }

            if (!isDuplicateSkuError(result)) {
                continue;
            }

            Product2 variant = variants[i];

            System.debug(
                LoggingLevel.ERROR,
                'ProductSkuService.resolveSkuCollisions: Duplicate SKU detected. ' +
                'Not allocating a new design number because duplicate SKU means duplicate ' +
                'design/material/size data. Shop_ID__c=' +
                (variant == null ? null : getStringField(variant, 'Shop_ID__c')) +
                ', SKU=' +
                (variant == null ? null : variant.StockKeepingUnit)
            );
        }

        return toRetry;
    }

    private static Set<String> getUsedSkus() {
        Set<String> usedSkus = new Set<String>();

        for (Product2 productRecord : [
            SELECT StockKeepingUnit
            FROM Product2
            WHERE StockKeepingUnit != null
        ]) {
            if (!String.isBlank(productRecord.StockKeepingUnit)) {
                usedSkus.add(
                    productRecord.StockKeepingUnit.trim().toUpperCase()
                );
            }
        }

        return usedSkus;
    }

    /**
     * Returns ALL Shopify jewelry-material reference labels in source order.
     *
     * Salesforce Material__c is a multi-select picklist, so the orchestration
     * service uses this method to populate every mapped material.
     *
     * SKU generation intentionally continues to use
     * deriveMaterialFromShopifyPayload(), which returns only the first material.
     */
    public static List<String> deriveMaterialsFromShopifyPayload(
        Map<String, Object> productPayload
    ) {
        List<String> materials = new List<String>();

        if (productPayload == null) {
            return materials;
        }

        if (
            productPayload.containsKey('metafields') &&
            productPayload.get('metafields') != null
        ) {
            try {
                List<Object> metafields =
                    (List<Object>) productPayload.get('metafields');

                for (Object metafieldObject : metafields) {
                    Map<String, Object> metafield =
                        (Map<String, Object>) metafieldObject;

                    if (metafield == null) {
                        continue;
                    }

                    String namespaceValue =
                        String.valueOf(metafield.get('namespace'));

                    String keyValue =
                        String.valueOf(metafield.get('key'));

                    if (
                        namespaceValue != 'shopify' ||
                        keyValue != 'jewelry-material'
                    ) {
                        continue;
                    }

                    Map<String, Object> references =
                        (Map<String, Object>) metafield.get('references');

                    if (references == null) {
                        continue;
                    }

                    List<Object> nodes =
                        (List<Object>) references.get('nodes');

                    if (nodes == null || nodes.isEmpty()) {
                        continue;
                    }

                    for (Object nodeObject : nodes) {
                        Map<String, Object> node =
                            (Map<String, Object>) nodeObject;

                        if (node == null) {
                            continue;
                        }

                        List<Object> fields =
                            (List<Object>) node.get('fields');

                        if (fields == null) {
                            continue;
                        }

                        for (Object fieldObject : fields) {
                            Map<String, Object> field =
                                (Map<String, Object>) fieldObject;

                            if (field == null) {
                                continue;
                            }

                            if (String.valueOf(field.get('key')) != 'label') {
                                continue;
                            }

                            String labelValue =
                                String.valueOf(field.get('value'));

                            if (
                                !String.isBlank(labelValue) &&
                                !materials.contains(labelValue.trim())
                            ) {
                                materials.add(labelValue.trim());
                            }
                        }
                    }
                }
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.WARN,
                    'ProductSkuService.deriveMaterialsFromShopifyPayload: Error parsing metafields. ' +
                    'Falling back to existing single-material derivation. Error=' +
                    e.getMessage()
                );
            }
        }

        /*
         * Preserve all existing fallback behavior when Shopify does not provide
         * material references. The existing method remains the source of truth
         * for keyword-based material derivation and SKU behavior.
         */
        if (materials.isEmpty()) {
            String fallbackMaterial =
                deriveMaterialFromShopifyPayload(productPayload);

            if (!String.isBlank(fallbackMaterial)) {
                materials.add(fallbackMaterial);
            }
        }

        return materials;
    }

    public static String deriveMaterialFromShopifyPayload(
        Map<String, Object> productPayload
    ) {
        if (productPayload == null) {
            return null;
        }

        if (
            productPayload.containsKey('metafields') &&
            productPayload.get('metafields') != null
        ) {
            try {
                List<Object> metafields =
                    (List<Object>) productPayload.get('metafields');

                for (Object metafieldObject : metafields) {
                    Map<String, Object> metafield =
                        (Map<String, Object>) metafieldObject;

                    if (metafield == null) {
                        continue;
                    }

                    String namespaceValue =
                        String.valueOf(metafield.get('namespace'));

                    String keyValue =
                        String.valueOf(metafield.get('key'));

                    if (
                        namespaceValue != 'shopify' ||
                        keyValue != 'jewelry-material'
                    ) {
                        continue;
                    }

                    Map<String, Object> references =
                        (Map<String, Object>) metafield.get('references');

                    if (references == null) {
                        continue;
                    }

                    List<Object> nodes =
                        (List<Object>) references.get('nodes');

                    if (nodes == null || nodes.isEmpty()) {
                        continue;
                    }

                    Map<String, Object> firstNode =
                        (Map<String, Object>) nodes[0];

                    if (firstNode == null) {
                        continue;
                    }

                    List<Object> fields =
                        (List<Object>) firstNode.get('fields');

                    if (fields == null) {
                        continue;
                    }

                    for (Object fieldObject : fields) {
                        Map<String, Object> field =
                            (Map<String, Object>) fieldObject;

                        if (field == null) {
                            continue;
                        }

                        if (String.valueOf(field.get('key')) != 'label') {
                            continue;
                        }

                        String labelValue =
                            String.valueOf(field.get('value'));

                        if (!String.isBlank(labelValue)) {
                            return labelValue;
                        }
                    }
                }
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.WARN,
                    'ProductSkuService.deriveMaterialFromShopifyPayload: Error parsing metafields. ' +
                    'Falling back to keyword scan. Error=' +
                    e.getMessage()
                );
            }
        }

        List<String> valuesToCheck = new List<String>();

        addIfPresent(valuesToCheck, productPayload.get('title'));
        addIfPresent(valuesToCheck, productPayload.get('handle'));
        addIfPresent(valuesToCheck, productPayload.get('tags'));
        addIfPresent(valuesToCheck, productPayload.get('product_type'));

        if (
            productPayload.containsKey('options') &&
            productPayload.get('options') != null
        ) {
            List<Object> options =
                (List<Object>) productPayload.get('options');

            for (Object optionObject : options) {
                Map<String, Object> optionMap =
                    (Map<String, Object>) optionObject;

                if (optionMap == null) {
                    continue;
                }

                addIfPresent(valuesToCheck, optionMap.get('name'));

                if (
                    optionMap.containsKey('values') &&
                    optionMap.get('values') != null
                ) {
                    for (Object optionValue : (List<Object>) optionMap.get('values')) {
                        addIfPresent(valuesToCheck, optionValue);
                    }
                }
            }
        }

        for (String value : valuesToCheck) {
            if (String.isBlank(value)) {
                continue;
            }

            String normalized = value.toLowerCase();

            if (
                normalized.contains('gold plated') ||
                normalized.contains('gold-plated')
            ) {
                return 'Gold Plated';
            }

            if (
                normalized.contains('silver plated') ||
                normalized.contains('silver-plated')
            ) {
                return 'Silver Plated';
            }

            if (normalized.contains('solid gold')) {
                return 'Solid Gold';
            }

            if (normalized.contains('white gold')) {
                return 'White Gold';
            }

            if (normalized.contains('rose gold')) {
                return 'Rose Gold Plated';
            }

            if (normalized.contains('gold')) {
                return 'Gold Plated';
            }

            if (
                normalized.contains('silver') ||
                normalized.contains('sterling')
            ) {
                return 'Silver Plated';
            }
        }

        return null;
    }

    private static Boolean shouldGenerateSku(Product2 variant) {
        if (variant == null) {
            return false;
        }

        if (variant.Type__c != 'Variant') {
            return false;
        }

        if (!String.isBlank(variant.StockKeepingUnit)) {
            return false;
        }

        return true;
    }

    private static String getTypeCode(Product2 variant) {
        String rawType = getStringField(variant, 'Product_Type__c');

        if (String.isBlank(rawType)) {
            rawType = getStringField(variant, 'Type_Code__c');
        }

        if (String.isBlank(rawType)) {
            rawType = variant == null ? null : variant.Family;
        }

        if (String.isBlank(rawType)) {
            return null;
        }

        String normalized = rawType.trim().toLowerCase();

        if (
            normalized == 'a' ||
            normalized == 'ac' ||
            normalized == 'accessory' ||
            normalized == 'accessories' ||
            normalized == 'jewelry accessory' ||
            normalized == 'jewelry accessories'
        ) {
            return 'A';
        }

        if (
            normalized == 'g' ||
            normalized == 'gv' ||
            normalized == 'gift voucher' ||
            normalized == 'gift vouchers' ||
            normalized == 'voucher' ||
            normalized == 'vouchers' ||
            normalized == 'e-gift voucher' ||
            normalized == 'egift voucher' ||
            normalized == 'e gift voucher' ||
            normalized == 'giftcard' ||
            normalized == 'gift card' ||
            normalized == 'gift cards'
        ) {
            return 'G';
        }

        if (
            normalized == 'r' ||
            normalized == 'rg' ||
            normalized == 'ring' ||
            normalized == 'rings'
        ) {
            return 'R';
        }

        if (
            normalized == 'n' ||
            normalized == 'nk' ||
            normalized == 'necklace' ||
            normalized == 'necklaces'
        ) {
            return 'N';
        }

        if (
            normalized == 'b' ||
            normalized == 'br' ||
            normalized == 'bracelet' ||
            normalized == 'bracelets'
        ) {
            return 'B';
        }

        if (
            normalized == 'e' ||
            normalized == 'er' ||
            normalized == 'earring' ||
            normalized == 'earrings' ||
            normalized == 'dangle' ||
            normalized == 'dangles' ||
            normalized == 'drop' ||
            normalized == 'drops' ||
            normalized == 'hoop' ||
            normalized == 'hoops' ||
            normalized == 'stud' ||
            normalized == 'studs' ||
            normalized == 'huggy' ||
            normalized == 'huggies'
        ) {
            return 'E';
        }

        if (
            normalized == 'st' ||
            normalized == 'set' ||
            normalized == 'sets' ||
            normalized == 'bundle' ||
            normalized == 'bundles'
        ) {
            return 'S';
        }

        return null;
    }

    private static String getMaterialCode(Product2 variant, String typeCode) {
        String rawMaterial = getStringField(variant, 'Metal_Colour__c');

        if (String.isBlank(rawMaterial)) {
            rawMaterial = getStringField(variant, 'Metal_Color__c');
        }

        if (String.isBlank(rawMaterial)) {
            rawMaterial = getStringField(variant, 'Material__c');
        }

        /*
         * Accessories and Gift Vouchers can safely use NA when material is blank.
         */
        if (String.isBlank(rawMaterial) && (typeCode == 'A' || typeCode == 'G')) {
            return 'NA';
        }

        if (String.isBlank(rawMaterial)) {
            return null;
        }

        String primaryMaterial = rawMaterial;

        if (primaryMaterial.contains(';')) {
            primaryMaterial = primaryMaterial.split(';')[0];
        }

        String normalized = primaryMaterial.trim().toLowerCase();

        if (
            normalized == 'na' ||
            normalized == 'n/a' ||
            normalized == 'not applicable' ||
            normalized == 'general' ||
            normalized == 'not material specific' ||
            normalized == 'not material-specific'
        ) {
            return 'NA';
        }

        if (
            normalized == 'gp' ||
            normalized == 'gold plated' ||
            normalized == 'gold-plated' ||
            normalized == '14k gold plated' ||
            normalized == '14k gold-plated' ||
            normalized == '18k gold plated' ||
            normalized == '18k gold-plated' ||
            normalized == 'gold vermeil' ||
            normalized == 'gold vermeil plated'
        ) {
            return 'GP';
        }

        if (
            normalized == 'sp' ||
            normalized == 'silver plated' ||
            normalized == 'silver-plated' ||
            normalized == 'silver' ||
            normalized == 'sterling silver' ||
            normalized == 'rhodium plated' ||
            normalized == 'rhodium-plated' ||
            normalized == 'rhodium plated silver' ||
            normalized == 'rhodium-plated silver'
        ) {
            return 'SP';
        }

        if (
            normalized == 'sg' ||
            normalized == 'solid gold' ||
            normalized == 'plain gold' ||
            normalized == 'real gold' ||
            normalized == 'gold' ||
            normalized == '14k gold' ||
            normalized == '18k gold'
        ) {
            return 'SG';
        }

        if (
            normalized == 'wg' ||
            normalized == 'white gold' ||
            normalized == 'white gold plated' ||
            normalized == 'white gold-plated'
        ) {
            return 'WG';
        }

        if (
            normalized == 'rp' ||
            normalized == 'rose gold' ||
            normalized == 'rose gold plated' ||
            normalized == 'rose gold-plated'
        ) {
            return 'RP';
        }

        return null;
    }

    private static String getDimensionCode(Product2 variant) {
        String rawDimension = resolveRawDimensionValue(variant);
        return encodeDimension(rawDimension);
    }

    private static String resolveRawDimensionValue(Product2 variant) {
        if (variant == null) {
            return null;
        }

        List<String> candidateFields = new List<String>{
            'Size__c',
            'Dimension__c',
            'Ring_Size__c',
            'Chain_Length__c',
            'Length__c'
        };

        for (String fieldApiName : candidateFields) {
            String value = getStringField(variant, fieldApiName);

            if (!String.isBlank(value)) {
                return value.trim();
            }
        }

        return extractDimensionFromNameOrTitle(variant);
    }

    private static String encodeDimension(String rawDimension) {
        if (String.isBlank(rawDimension)) {
            return '000';
        }

        String originalValue = rawDimension.trim();
        String value = originalValue.toLowerCase();

        if (
            value == '-' ||
            value == 'none' ||
            value == 'no size' ||
            value == 'one size' ||
            value == 'onesize' ||
            value == 'one-size' ||
            value == 'default title'
        ) {
            return '000';
        }

        /*
         * Shopify ring size may come as:
         *   UK J 1/2 (US 5)
         *   UK L 1/2 (US 6)
         *   UK N 1/2 (US 7)
         *
         * Use the US size inside parentheses first.
         * This avoids incorrectly reading the UK 1/2 fraction as size 1.
         */
        Pattern parenthesizedUsSizePattern =
            Pattern.compile('(?i)\\(\\s*US\\s*([0-9]+(\\.[0-9]+)?)\\s*\\)');

        Matcher parenthesizedUsSizeMatcher =
            parenthesizedUsSizePattern.matcher(originalValue);

        if (parenthesizedUsSizeMatcher.find()) {
            return encodeNumericDimension(
                parenthesizedUsSizeMatcher.group(1),
                rawDimension
            );
        }

        Pattern usSizePattern =
            Pattern.compile('(?i)\\bUS\\s*([0-9]+(\\.[0-9]+)?)\\b');

        Matcher usSizeMatcher = usSizePattern.matcher(originalValue);

        if (usSizeMatcher.find()) {
            return encodeNumericDimension(
                usSizeMatcher.group(1),
                rawDimension
            );
        }

        value = value.replace('size', '');
        value = value.replace('ring', '');
        value = value.replace('uk', '');
        value = value.replace('us', '');
        value = value.replace('"', '');
        value = value.replace('inches', '');
        value = value.replace('inch', '');
        value = value.replace('in', '');
        value = value.trim();

        Pattern numberPattern = Pattern.compile('([0-9]+(\\.[0-9]+)?)');
        Matcher numberMatcher = numberPattern.matcher(value);

        if (!numberMatcher.find()) {
            System.debug(
                LoggingLevel.WARN,
                'ProductSkuService.encodeDimension: Could not parse dimension "' +
                rawDimension +
                '". Using 000.'
            );

            return '000';
        }

        return encodeNumericDimension(numberMatcher.group(1), rawDimension);
    }

    private static String encodeNumericDimension(
        String numericValueText,
        String rawDimension
    ) {
        Decimal numericValue;

        try {
            numericValue = Decimal.valueOf(numericValueText);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'ProductSkuService.encodeNumericDimension: Invalid numeric dimension "' +
                rawDimension +
                '". Error=' +
                e.getMessage()
            );

            return '000';
        }

        Integer encodedNumber =
            Integer.valueOf((numericValue * 10).setScale(0));

        return formatNumber(encodedNumber, 3);
    }

    private static String extractDimensionFromNameOrTitle(Product2 variant) {
        if (variant == null || String.isBlank(variant.Name)) {
            return null;
        }

        Pattern parenthesizedUsSizePattern =
            Pattern.compile('(?i)\\(\\s*US\\s*([0-9]+(\\.[0-9]+)?)\\s*\\)');

        Matcher parenthesizedUsSizeMatcher =
            parenthesizedUsSizePattern.matcher(variant.Name);

        if (parenthesizedUsSizeMatcher.find()) {
            return parenthesizedUsSizeMatcher.group(1);
        }

        Pattern quotedNumber = Pattern.compile('"([0-9]+(\\.[0-9]+)?)"');
        Matcher quotedMatcher = quotedNumber.matcher(variant.Name);

        if (quotedMatcher.find()) {
            return quotedMatcher.group(1);
        }

        Pattern sizeNumber =
            Pattern.compile('(?i)size\\s+([0-9]+(\\.[0-9]+)?)');

        Matcher sizeMatcher = sizeNumber.matcher(variant.Name);

        if (sizeMatcher.find()) {
            return sizeMatcher.group(1);
        }

        return null;
    }

    private static String buildStyleKey(Product2 variant, String typeCode) {
        String parentValue = null;

        if (variant != null && variant.Parent__c != null) {
            parentValue = String.valueOf(variant.Parent__c);
        }

        if (
            String.isBlank(parentValue) &&
            variant != null &&
            variant.Parent__r != null
        ) {
            parentValue = getStringField(variant.Parent__r, 'Shop_ID__c');
        }

        if (String.isBlank(parentValue) && variant != null) {
            parentValue = getStringField(variant, 'Parent_SKU_Key__c');
        }

        if (String.isBlank(parentValue) && variant != null) {
            parentValue = getStringField(variant, 'SF_Parent_Product_Name__c');
        }

        if (
            String.isBlank(parentValue) &&
            variant != null &&
            variant.Parent__r != null
        ) {
            parentValue = getStringField(variant.Parent__r, 'Name');
        }

        if (String.isBlank(parentValue) && variant != null) {
            parentValue = normalizeDesignName(variant.Name);
        }

        return typeCode + '|' + String.valueOf(parentValue).trim().toLowerCase();
    }

    private static Integer findExistingStyleNumberForVariant(
        Product2 variant,
        String typeCode
    ) {
        if (variant == null || String.isBlank(typeCode)) {
            return null;
        }

        /*
         * First priority:
         * Parent Product SKU is the source of truth.
         *
         * Sometimes inbound variants only contain Parent__r.Shop_ID__c and not Parent__c.
         * In that case, query the parent Product by Shopify Product ID and use its short SKU.
         */
        if (
            variant.Parent__r != null &&
            !String.isBlank(getStringField(variant.Parent__r, 'Shop_ID__c'))
        ) {
            String parentShopId =
                getStringField(variant.Parent__r, 'Shop_ID__c');

            List<Product2> parentProductsByShopId = [
                SELECT Id, StockKeepingUnit
                FROM Product2
                WHERE Shop_ID__c = :parentShopId
                AND Type__c = 'Product'
                LIMIT 1
            ];

            if (!parentProductsByShopId.isEmpty()) {
                Integer parentStyleNumber =
                    getStyleNumberFromSku(
                        parentProductsByShopId[0].StockKeepingUnit
                    );

                if (parentStyleNumber != null) {
                    return parentStyleNumber;
                }
            }
        }

        /*
         * Second priority:
         * Use parent relationship SKU if it was already queried.
         */
        if (variant.Parent__r != null) {
            String parentSkuFromRelationship =
                getStringField(variant.Parent__r, 'StockKeepingUnit');

            if (!String.isBlank(parentSkuFromRelationship)) {
                Integer parentStyleNumber =
                    getStyleNumberFromSku(parentSkuFromRelationship);

                if (parentStyleNumber != null) {
                    return parentStyleNumber;
                }
            }
        }

        /*
         * Third priority:
         * Use Parent__c to query parent Product and existing sibling variants.
         */
        if (variant.Parent__c != null) {
            List<Product2> parentProducts = [
                SELECT Id, StockKeepingUnit
                FROM Product2
                WHERE Id = :variant.Parent__c
                LIMIT 1
            ];

            if (!parentProducts.isEmpty()) {
                Integer parentStyleNumber =
                    getStyleNumberFromSku(parentProducts[0].StockKeepingUnit);

                if (parentStyleNumber != null) {
                    return parentStyleNumber;
                }
            }

            for (Product2 siblingVariant : [
                SELECT Id, StockKeepingUnit
                FROM Product2
                WHERE Parent__c = :variant.Parent__c
                AND Type__c = 'Variant'
                AND StockKeepingUnit != null
                ORDER BY CreatedDate ASC
                LIMIT 200
            ]) {
                Integer existingStyleNumber =
                    getStyleNumberFromSku(siblingVariant.StockKeepingUnit);

                if (existingStyleNumber != null) {
                    return existingStyleNumber;
                }
            }
        }

        return null;
    }

    private static Map<String, Set<Integer>> getUsedStyleNumbersByTypeCode() {
        Map<String, Set<Integer>> usedByTypeCode =
            new Map<String, Set<Integer>>();

        for (Product2 productRecord : [
            SELECT StockKeepingUnit
            FROM Product2
            WHERE StockKeepingUnit != null
        ]) {
            String typeCode = getTypeCodeFromSku(productRecord.StockKeepingUnit);
            Integer styleNumber =
                getStyleNumberFromSku(productRecord.StockKeepingUnit);

            if (String.isBlank(typeCode) || styleNumber == null) {
                continue;
            }

            if (!usedByTypeCode.containsKey(typeCode)) {
                usedByTypeCode.put(typeCode, new Set<Integer>());
            }

            usedByTypeCode.get(typeCode).add(styleNumber);
        }

        return usedByTypeCode;
    }

    private static Set<Integer> getUsedStyleNumbersForType(
        Map<String, Set<Integer>> usedStyleNumbersByTypeCode,
        String typeCode
    ) {
        if (usedStyleNumbersByTypeCode == null) {
            usedStyleNumbersByTypeCode = new Map<String, Set<Integer>>();
        }

        if (String.isBlank(typeCode)) {
            typeCode = 'UNKNOWN';
        }

        if (!usedStyleNumbersByTypeCode.containsKey(typeCode)) {
            usedStyleNumbersByTypeCode.put(typeCode, new Set<Integer>());
        }

        return usedStyleNumbersByTypeCode.get(typeCode);
    }

    private static String getTypeCodeFromSku(String sku) {
        if (String.isBlank(sku)) {
            return null;
        }

        String value = sku.trim().toUpperCase();

        /*
         * New format:
         *   R0026SG070 -> R
         *   N0001GP000 -> N
         *
         * Parent short format:
         *   R0026 -> R
         *   N0001 -> N
         */
        if (!value.contains('-') && value.length() >= 5) {
            String typeCode = value.substring(0, 1);

            if (VALID_TYPE_CODES.contains(typeCode)) {
                return typeCode;
            }

            return null;
        }

        /*
         * Backward compatibility for old hyphenated format:
         *   ES-RG-G-0142-070
         */
        if (value.contains('-')) {
            List<String> parts = value.split('-');

            if (parts.size() >= 2) {
                String oldType = parts[1];

                if (oldType == 'RG' || oldType == 'R') return 'R';
                if (oldType == 'NK' || oldType == 'N') return 'N';
                if (oldType == 'BR' || oldType == 'B') return 'B';
                if (oldType == 'ER' || oldType == 'E') return 'E';
                if (oldType == 'AC' || oldType == 'A') return 'A';
                if (oldType == 'GV' || oldType == 'G') return 'G';
                if (oldType == 'ST' || oldType == 'S') return 'S';
            }
        }

        return null;
    }

    private static Integer getStyleNumberFromSku(String sku) {
        if (String.isBlank(sku)) {
            return null;
        }

        String value = sku.trim().toUpperCase();

        /*
         * New full SKU:
         *   R0042GP075 -> style 0042
         *
         * New parent short SKU:
         *   R0042 -> style 0042
         */
        if (!value.contains('-')) {
            if (value.length() >= 5) {
                String styleCode = value.substring(1, 5);

                if (!isNumeric(styleCode)) {
                    return null;
                }

                try {
                    return Integer.valueOf(styleCode);
                } catch (Exception e) {
                    return null;
                }
            }

            return null;
        }

        /*
         * Backward compatibility for old hyphenated format:
         *   ES-RG-G-0142-070
         */
        List<String> parts = value.split('-');

        if (parts.size() >= 4 && isNumeric(parts[3])) {
            try {
                return Integer.valueOf(parts[3]);
            } catch (Exception e) {
                return null;
            }
        }

        return null;
    }

    private static Integer findNextFreeStyleNumber(
        Set<Integer> usedNumbers,
        Integer startNumber
    ) {
        if (usedNumbers == null) {
            usedNumbers = new Set<Integer>();
        }

        if (startNumber == null || startNumber < 1) {
            startNumber = 1;
        }

        for (
            Integer candidate = startNumber;
            candidate <= MAX_STYLE_SCAN_ATTEMPTS;
            candidate++
        ) {
            if (!usedNumbers.contains(candidate)) {
                return candidate;
            }
        }

        return null;
    }

    private static String buildSku(
        String typeCode,
        String materialCode,
        String styleCode,
        String dimensionCode
    ) {
        if (String.isBlank(typeCode)) {
            return null;
        }

        if (String.isBlank(styleCode)) {
            return null;
        }

        if (String.isBlank(materialCode)) {
            materialCode = 'NA';
        }

        if (String.isBlank(dimensionCode)) {
            dimensionCode = '000';
        }

        return typeCode + styleCode + materialCode + dimensionCode;
    }

    private static String buildShortSku(
        String typeCode,
        String styleCode
    ) {
        if (String.isBlank(typeCode)) {
            return null;
        }

        if (String.isBlank(styleCode)) {
            return null;
        }

        return typeCode + styleCode;
    }

    public static String buildShortSkuForVariant(Product2 variant) {
        if (
            variant == null ||
            String.isBlank(variant.StockKeepingUnit)
        ) {
            return null;
        }

        String fullSku = variant.StockKeepingUnit.trim().toUpperCase();

        /*
         * Full SKU:
         *   R0042GP075 -> R0042
         *   N0043GP000 -> N0043
         *   A0045NA000 -> A0045
         *   G0047NA000 -> G0047
         */
        return fullSku.length() >= 5
            ? fullSku.substring(0, 5)
            : null;
    }

    private static Boolean isDuplicateSkuError(Database.UpsertResult result) {
        if (result == null || result.isSuccess()) {
            return false;
        }

        for (Database.Error errorRecord : result.getErrors()) {
            if (errorRecord == null) {
                continue;
            }

            Boolean isDuplicateValue =
                errorRecord.getStatusCode() == StatusCode.DUPLICATE_VALUE;

            String message = errorRecord.getMessage();

            Boolean mentionsSku =
                message != null &&
                message.toLowerCase().contains('sku');

            if (isDuplicateValue && mentionsSku) {
                return true;
            }
        }

        return false;
    }

    private static String formatNumber(Integer numberValue, Integer width) {
        if (numberValue == null) {
            return null;
        }

        String formatted = String.valueOf(numberValue).leftPad(width, '0');

        if (width == 3 && formatted.length() > 3) {
            formatted = formatted.substring(formatted.length() - 3);
        }

        return formatted;
    }

    private static String getStringField(Product2 productRecord, String fieldApiName) {
        if (productRecord == null || String.isBlank(fieldApiName)) {
            return null;
        }

        if (!PRODUCT2_FIELD_MAP.containsKey(fieldApiName)) {
            return null;
        }

        try {
            Object value = productRecord.get(fieldApiName);

            if (value == null) {
                return null;
            }

            String stringValue = String.valueOf(value);

            return String.isBlank(stringValue) ? null : stringValue;
        } catch (SObjectException e) {
            return null;
        }
    }

    private static void setFieldIfPresent(
        Product2 productRecord,
        String fieldApiName,
        Object value
    ) {
        if (
            productRecord == null ||
            String.isBlank(fieldApiName) ||
            value == null
        ) {
            return;
        }

        if (PRODUCT2_FIELD_MAP.containsKey(fieldApiName)) {
            productRecord.put(fieldApiName, value);
        }
    }

    private static void addIfPresent(List<String> values, Object rawValue) {
        if (values == null || rawValue == null) {
            return;
        }

        String value = String.valueOf(rawValue);

        if (!String.isBlank(value)) {
            values.add(value);
        }
    }

    private static String normalizeDesignName(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String normalized = value.trim().toLowerCase();

        normalized = normalized.replace('-', ' ');
        normalized = normalized.replace('_', ' ');
        normalized = normalized.replaceAll('[^a-z0-9 ]', ' ');
        normalized = normalized.replaceAll('\\s+', ' ');
        normalized = normalized.trim();

        /*
         * Remove common size text from design key.
         * This helps variants of the same ring design group together.
         */
        normalized = normalized.replaceAll(
            '(?i)\\buk\\s+[a-z]\\s*1\\s*2\\s*us\\s*[0-9]+\\b',
            ''
        );

        normalized = normalized.replaceAll(
            '(?i)\\buk\\s+[a-z]\\s*1/2\\s*us\\s*[0-9]+\\b',
            ''
        );

        normalized = normalized.replaceAll(
            '(?i)\\bus\\s*[0-9]+(\\.[0-9]+)?\\b',
            ''
        );

        normalized = normalized.replaceAll(
            '(?i)\\bsize\\s*[0-9]+(\\.[0-9]+)?\\b',
            ''
        );

        normalized = normalized.replaceAll('\\s+', ' ');
        normalized = normalized.trim();

        return normalized;
    }

    private static Boolean isNumeric(String value) {
        if (String.isBlank(value)) {
            return false;
        }

        return Pattern.compile('^[0-9]+$').matcher(value).matches();
    }
}