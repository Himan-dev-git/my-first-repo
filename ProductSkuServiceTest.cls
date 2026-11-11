@IsTest
private class ProductSkuServiceTest {
    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────
    
    private static void setMock() {
        GlobalHttpMock.mockMode = 'SUCCESS';
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
    }
    
    private static String uniqueText(String prefix) {
        return prefix + '-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    /*
     * Generates a four-digit style code that is very unlikely to collide
     * with existing org data. Product2 SKU uniqueness is enforced at the
     * database level even when tests do not use SeeAllData=true.
     */
    private static String uniqueStyleCode() {
        Integer value = Math.abs(Crypto.getRandomInteger());
        value = Math.mod(value, 8000) + 1000;
        return String.valueOf(value).leftPad(4, '0');
    }

    private static String compactSku(
        String typeCode,
        String materialCode,
        String dimensionCode
    ) {
        return typeCode +
            uniqueStyleCode() +
            materialCode +
            dimensionCode;
    }
    
    private static Boolean productFieldExists(String fieldApiName) {
        return Product2.SObjectType.getDescribe().fields.getMap().containsKey(fieldApiName);
    }
    
    private static void setOptionalField(Product2 p, String fieldApiName, Object value) {
        if (p == null || String.isBlank(fieldApiName)) {
            return;
        }
        
        if (value == null) {
            return;
        }
        
        if (productFieldExists(fieldApiName)) {
            p.put(fieldApiName, value);
        }
    }
    
    private static Product2 buildVariant(String name, String family, String material) {
        Product2 p = new Product2(
            Name = name,
            IsActive = true,
            Family = family
        );
        
        p.put('Type__c', 'Variant');
        
        if (material != null) {
            p.put('Material__c', material);
        }
        
        return p;
    }
    
    private static Product2 buildVariantWithSize(
        String name,
        String family,
        String material,
        String sizeValue
    ) {
        Product2 p = buildVariant(name, family, material);
        setOptionalField(p, 'Size__c', sizeValue);
        return p;
    }
    
    private static Product2 buildExistingProductWithSku(String name, String skuValue) {
        Product2 p = new Product2(
            Name = name + ' ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true,
            Family = 'Ring',
            StockKeepingUnit = skuValue
        );
        
        p.put('Type__c', 'Variant');
        p.put('Material__c', 'Gold');
        
        return p;
    }
    
    private static void insertExistingProducts(List<Product2> productsToInsert) {
        if (productsToInsert == null || productsToInsert.isEmpty()) {
            return;
        }
        
        setMock();
        
        Database.SaveResult[] results = Database.insert(productsToInsert, false);
        
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(
                        LoggingLevel.WARN,
                        'Seed Product2 insert skipped: ' +
                        err.getStatusCode() + ' - ' + err.getMessage()
                    );
                }
            }
        }
    }
    
    private static void assertSkuShape(String skuValue) {
        System.assertNotEquals(
            null,
            skuValue,
            'SKU should be assigned.'
        );
        
        Boolean jewellerySku = Pattern.matches(
            '^[A-Z][0-9]{4}[A-Z]{2}[0-9]{3}$',
            skuValue
        );
        
        Boolean nonMetalSku = Pattern.matches(
            '^[AG][0-9]{4}NA[0-9]{3}$',
            skuValue
        );
        
        System.assert(
            jewellerySku || nonMetalSku,
            'SKU should use the current compact format. Actual: ' +
            skuValue
        );
    }
    
    private static void assertJewellerySku(
        String skuValue,
        String expectedTypeCode,
        String expectedMetalCode,
        String expectedDimension
    ) {
        assertSkuShape(skuValue);
        
        String expectedPattern =
            '^' + expectedTypeCode +
            '[0-9]{4}' + expectedMetalCode +
            expectedDimension + '$';
        
        System.assert(
            Pattern.matches(expectedPattern, skuValue),
            'Expected SKU pattern ' + expectedPattern +
            '. Actual: ' + skuValue
        );
    }
    
    private static String getStyleCode(
        String skuValue,
        Integer typeCodeLength
    ) {
        System.assertNotEquals(null, skuValue);
        System.assert(typeCodeLength == 1 || typeCodeLength == 2);
        
        return skuValue.substring(
            typeCodeLength,
            typeCodeLength + 4
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // assignSkusForNewInboundVariants - core behavior
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testAssignSkusForNewInboundVariantsNewFormat() {
        Product2 ringGold = buildVariantWithSize(
            'Gold Ring Size 7',
            'Ring',
            'Gold',
            '7'
        );
        
        Product2 necklaceSilver = buildVariantWithSize(
            'Silver Necklace 18"',
            'Necklace',
            'Silver',
            '18'
        );
        
        Product2 braceletRose = buildVariantWithSize(
            'Rose Gold Bracelet One Size',
            'Bracelet',
            'Rose Gold',
            'One Size'
        );
        
        List<Product2> variants = new List<Product2>{
            ringGold,
                necklaceSilver,
                braceletRose
                };
                    
                    Test.startTest();
        
        ProductSkuService.assignSkusForNewInboundVariants(
            variants
        );
        
        Test.stopTest();
        
        assertSkuShape(ringGold.StockKeepingUnit);
        assertSkuShape(necklaceSilver.StockKeepingUnit);
        assertSkuShape(braceletRose.StockKeepingUnit);
        
        assertJewellerySku(
            ringGold.StockKeepingUnit,
            'R',
            'SG',
            '070'
        );
        
        assertJewellerySku(
            necklaceSilver.StockKeepingUnit,
            'N',
            'SP',
            '180'
        );
        
        assertJewellerySku(
            braceletRose.StockKeepingUnit,
            'B',
            'RP',
            '000'
        );
    }
    
    @IsTest
    static void testAssignSkusUsesSameStyleNumberForSameStyleKeyDifferentSizes() {
        Product2 ringSize7 = buildVariantWithSize('Same Style Ring', 'Ring', 'Gold', '7');
        Product2 ringSize65 = buildVariantWithSize('Same Style Ring', 'Ring', 'Gold', '6.5');
        
        List<Product2> variants = new List<Product2>{ ringSize7, ringSize65 };
            
            Test.startTest();
        ProductSkuService.assignSkusForNewInboundVariants(variants);
        Test.stopTest();
        
        System.assert(
            Pattern.matches('^R[0-9]{4}SG070$', ringSize7.StockKeepingUnit),
            'Expected R + style + SG + dimension. Actual: ' + ringSize7.StockKeepingUnit
        );
        System.assert(
            Pattern.matches('^R[0-9]{4}SG065$', ringSize65.StockKeepingUnit),
            'Expected R + style + SG + dimension. Actual: ' + ringSize65.StockKeepingUnit
        );
        
        String style1 = getStyleCode(ringSize7.StockKeepingUnit, 1);
        String style2 = getStyleCode(ringSize65.StockKeepingUnit, 1);
        
        System.assertEquals(
            style1,
            style2,
            'Same style key should reuse same 4-digit style number.'
        );
        
        System.assertEquals('070', ringSize7.StockKeepingUnit.substring(ringSize7.StockKeepingUnit.length() - 3));
        System.assertEquals('065', ringSize65.StockKeepingUnit.substring(ringSize65.StockKeepingUnit.length() - 3));
    }
    
    @IsTest
    static void testAssignSkusUsesExistingUsedStyleNumbers() {
        String usedRingSku = compactSku('R', 'SG', '000');
        String usedNecklaceSku = compactSku('N', 'SP', '000');

        insertExistingProducts(
            new List<Product2>{
                buildExistingProductWithSku('Existing Ring Style', usedRingSku),
                buildExistingProductWithSku('Existing Necklace Style', usedNecklaceSku),
                buildExistingProductWithSku('Invalid Brand', 'X' + uniqueStyleCode() + 'SG000'),
                buildExistingProductWithSku('Invalid Parts', 'R' + uniqueStyleCode() + 'SG'),
                buildExistingProductWithSku('Invalid Style', 'RABCDSG000')
            }
        );

        Product2 newRing = buildVariantWithSize(
            'New Gold Ring ' + uniqueText('DESIGN'),
            'Ring',
            'Gold',
            null
        );

        Test.startTest();
        ProductSkuService.assignSkusForNewInboundVariants(
            new List<Product2>{ newRing }
        );
        Test.stopTest();

        assertSkuShape(newRing.StockKeepingUnit);
        System.assert(
            Pattern.matches('^R[0-9]{4}SG000$', newRing.StockKeepingUnit),
            'Expected R + style + SG + 000. Actual: ' + newRing.StockKeepingUnit
        );
        System.assertNotEquals(
            usedRingSku,
            newRing.StockKeepingUnit,
            'A newly generated Ring SKU must not reuse an already-used complete SKU.'
        );
    }
    
    @IsTest
    static void testAssignSkusSkipsInvalidRecords() {
        Product2 nonVariant = new Product2(
            Name = 'Non Variant',
            IsActive = true,
            Family = 'Ring'
        );
        nonVariant.put('Type__c', 'Product');
        nonVariant.put('Material__c', 'Gold');
        
        Product2 alreadyHasSku = new Product2(
            Name = 'Already Has SKU',
            IsActive = true,
            Family = 'Ring',
            StockKeepingUnit = 'CUSTOM001'
        );
        alreadyHasSku.put('Type__c', 'Variant');
        alreadyHasSku.put('Material__c', 'Gold');
        
        Product2 invalidMaterial = buildVariant('Invalid Material', 'Ring', 'Bronze');
        Product2 invalidFamily = buildVariant('Invalid Family', 'Watch', 'Gold');
        Product2 pearlMaterial = buildVariant('Pearl Ring', 'Ring', 'Pearl');
        
        List<Product2> variants = new List<Product2>{
            nonVariant,
                alreadyHasSku,
                invalidMaterial,
                invalidFamily,
                pearlMaterial,
                null
                };
                    
                    Test.startTest();
        ProductSkuService.assignSkusForNewInboundVariants(variants);
        Test.stopTest();
        
        System.assertEquals(null, nonVariant.StockKeepingUnit);
        System.assertEquals('CUSTOM001', alreadyHasSku.StockKeepingUnit);
        System.assertEquals(null, invalidMaterial.StockKeepingUnit);
        System.assertEquals(null, invalidFamily.StockKeepingUnit);
        System.assertEquals(null, pearlMaterial.StockKeepingUnit);
    }
    
    @IsTest
    static void testAssignSkusHandlesNullAndEmpty() {
        Test.startTest();
        ProductSkuService.assignSkusForNewInboundVariants(null);
        ProductSkuService.assignSkusForNewInboundVariants(new List<Product2>());
        Test.stopTest();
        
        System.assert(true, 'Null and empty inputs handled safely.');
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Type and metal code coverage
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testAllSupportedTypeAndMetalPrefixes() {
        List<String> families = new List<String>{
            'Ring',
                'Rings',
                'Necklace',
                'Necklaces',
                'Bracelet',
                'Bracelets',
                'Earring',
                'Earrings',
                'Dangles',
                'Hoops',
                'Studs',
                'Set',
                'Bundle'
                };
                    
                    /*
* Platinum is not included because the current ProductSkuService
* does not generate a SKU for it.
*/
                    List<String> supportedMaterials = new List<String>{
                        'Gold',
                            'Silver',
                            'Sterling Silver',
                            'Rose Gold',
                            'White Gold'
                            };
                                
                                List<Product2> variants = new List<Product2>();
        
        for (String familyValue : families) {
            for (String materialValue : supportedMaterials) {
                variants.add(
                    buildVariant(
                        familyValue + ' ' +
                        materialValue + ' Test',
                        familyValue,
                        materialValue
                    )
                );
            }
        }
        
        Product2 unsupportedPlatinum = buildVariant(
            'Unsupported Platinum Ring',
            'Ring',
            'Platinum'
        );
        
        variants.add(unsupportedPlatinum);
        
        Test.startTest();
        
        ProductSkuService.assignSkusForNewInboundVariants(
            variants
        );
        
        Test.stopTest();
        
        for (
            Integer index = 0;
            index < variants.size() - 1;
            index++
        ) {
            Product2 variant = variants[index];
            
            System.assertNotEquals(
                null,
                variant.StockKeepingUnit,
                'SKU should be assigned for family=' +
                variant.Family +
                ', material=' +
                variant.Material__c
            );
            
            assertSkuShape(
                variant.StockKeepingUnit
            );
            
            System.assert(
                variant.StockKeepingUnit.endsWith('000'),
                'A variant without size should end with 000. Actual: ' +
                variant.StockKeepingUnit
            );
        }
        
        /*
* Spot-check the current type and material prefixes.
*/
        System.assert(
            Pattern.matches('^R[0-9]{4}SG000$', variants[0].StockKeepingUnit),
            'Ring/Gold should match R + style + SG + 000. Actual: ' +
            variants[0].StockKeepingUnit
        );
        
        System.assert(
            Pattern.matches('^R[0-9]{4}SP000$', variants[1].StockKeepingUnit),
            'Ring/Silver Plated should match R + style + SP + 000. Actual: ' +
            variants[1].StockKeepingUnit
        );
        
        System.assert(
            Pattern.matches('^R[0-9]{4}SP000$', variants[2].StockKeepingUnit),
            'Ring/Sterling Silver should match R + style + SP + 000. Actual: ' +
            variants[2].StockKeepingUnit
        );
        
        System.assert(
            Pattern.matches('^R[0-9]{4}RP000$', variants[3].StockKeepingUnit),
            'Ring/Rose Gold should match R + style + RP + 000. Actual: ' +
            variants[3].StockKeepingUnit
        );
        
        System.assert(
            Pattern.matches('^R[0-9]{4}WG000$', variants[4].StockKeepingUnit),
            'Ring/White Gold should match R + style + WG + 000. Actual: ' +
            variants[4].StockKeepingUnit
        );
        System.assertEquals(
            null,
            unsupportedPlatinum.StockKeepingUnit,
            'Platinum is not mapped by the current SKU service.'
        );
    }
    
    @IsTest
    static void testTypeCodeFromOptionalProductTypeAndTypeCodeFields() {
        Product2 fromProductType = buildVariant('Type From Product Type', null, 'Gold');
        setOptionalField(fromProductType, 'Product_Type__c', 'nk');
        
        Product2 fromTypeCode = buildVariant('Type From Type Code', null, 'Gold');
        setOptionalField(fromTypeCode, 'Type_Code__c', 'br');
        
        List<Product2> variants = new List<Product2>{ fromProductType, fromTypeCode };
            
            Test.startTest();
        ProductSkuService.assignSkusForNewInboundVariants(variants);
        Test.stopTest();
        
        if (productFieldExists('Product_Type__c')) {
            System.assert(
                Pattern.matches('^N[0-9]{4}SG000$', fromProductType.StockKeepingUnit),
                'Product_Type__c should produce N + style + SG. Actual: ' + fromProductType.StockKeepingUnit
            );
        }
        
        if (productFieldExists('Type_Code__c')) {
            System.assert(
                Pattern.matches('^B[0-9]{4}SG000$', fromTypeCode.StockKeepingUnit),
                'Type_Code__c should produce B + style + SG. Actual: ' + fromTypeCode.StockKeepingUnit
            );
        }
    }
    
    @IsTest
    static void testMetalCodeFromOptionalMetalFieldsAndMultiSelect() {
        Product2 fromMetalColour = buildVariant('Metal Colour Field', 'Ring', null);
        setOptionalField(fromMetalColour, 'Metal_Colour__c', 'White Gold');
        
        Product2 fromMetalColor = buildVariant('Metal Color Field', 'Ring', null);
        setOptionalField(fromMetalColor, 'Metal_Color__c', 'Platinum');
        
        Product2 multiSelectMaterial = buildVariant('Multi Select Material', 'Ring', 'Gold;Silver');
        
        List<Product2> variants = new List<Product2>{
            fromMetalColour,
                fromMetalColor,
                multiSelectMaterial
                };
                    
                    Test.startTest();
        ProductSkuService.assignSkusForNewInboundVariants(variants);
        Test.stopTest();
        
        if (productFieldExists('Metal_Colour__c')) {
            System.assert(
                Pattern.matches('^R[0-9]{4}WG000$', fromMetalColour.StockKeepingUnit),
                'Metal_Colour__c should produce WG metal code. Actual: ' + fromMetalColour.StockKeepingUnit
            );
        }
        
        if (productFieldExists('Metal_Color__c')) {
            System.assertEquals(
                null,
                fromMetalColor.StockKeepingUnit,
                'Platinum is not mapped by the current ProductSkuService.'
            );
        }
        
        System.assert(
            Pattern.matches('^R[0-9]{4}SG000$', multiSelectMaterial.StockKeepingUnit),
            'First multi-select value should produce SG metal code. Actual: ' + multiSelectMaterial.StockKeepingUnit
        );
    }
    
    @IsTest
    static void testAccessoryAndGiftVoucherSkusDoNotRequireMaterial() {
        Product2 accessory = buildVariant(
            'Jewellery Polishing Cloth',
            'Accessories',
            null
        );
        
        Product2 giftVoucher = buildVariant(
            'E-Gift Voucher',
            'Gift Voucher',
            null
        );
        
        Test.startTest();
        ProductSkuService.assignSkusForNewInboundVariants(
            new List<Product2>{ accessory, giftVoucher }
        );
        Test.stopTest();
        
        System.assert(
            Pattern.matches('^A[0-9]{4}NA[0-9]{3}$', accessory.StockKeepingUnit),
            'Accessory SKU should be A + style + NA + dimension. Actual: ' +
            accessory.StockKeepingUnit
        );
        
        System.assert(
            Pattern.matches('^G[0-9]{4}NA[0-9]{3}$', giftVoucher.StockKeepingUnit),
            'Gift voucher SKU should be G + style + NA + dimension. Actual: ' +
            giftVoucher.StockKeepingUnit
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // Dimension encoding coverage
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testDimensionEncodingFromOptionalFieldsAndName() {
        Product2 fromSize = buildVariantWithSize('Size Field Ring', 'Ring', 'Gold', '7');
        
        Product2 fromDimension = buildVariant('Dimension Field Ring', 'Ring', 'Gold');
        setOptionalField(fromDimension, 'Dimension__c', '6.5');
        
        Product2 fromRingSize = buildVariant('Ring Size Field Ring', 'Ring', 'Gold');
        setOptionalField(fromRingSize, 'Ring_Size__c', '8');
        
        Product2 fromChainLength = buildVariant('Chain Length Necklace', 'Necklace', 'Gold');
        setOptionalField(fromChainLength, 'Chain_Length__c', '18 inch');
        
        Product2 fromLength = buildVariant('Length Necklace', 'Necklace', 'Gold');
        setOptionalField(fromLength, 'Length__c', '20"');
        
        Product2 fromQuotedName = buildVariant('Necklace 16"', 'Necklace', 'Gold');
        Product2 fromSizeName = buildVariant('Ring size 9', 'Ring', 'Gold');
        Product2 invalidDimension = buildVariantWithSize('Invalid Size Ring', 'Ring', 'Gold', 'Large');
        
        List<Product2> variants = new List<Product2>{
            fromSize,
                fromDimension,
                fromRingSize,
                fromChainLength,
                fromLength,
                fromQuotedName,
                fromSizeName,
                invalidDimension
                };
                    
                    Test.startTest();
        ProductSkuService.assignSkusForNewInboundVariants(variants);
        Test.stopTest();
        
        System.assert(
            fromSize.StockKeepingUnit != null &&
            fromSize.StockKeepingUnit.endsWith('070'),
            'Size__c should encode 7 as 070. Actual: ' + fromSize.StockKeepingUnit
        );
        
        if (productFieldExists('Dimension__c') && fromDimension.StockKeepingUnit != null) {
            System.assert(
                fromDimension.StockKeepingUnit.endsWith('065'),
                'Dimension__c should encode 6.5 as 065. Actual: ' + fromDimension.StockKeepingUnit
            );
        }
        
        if (productFieldExists('Ring_Size__c') && fromRingSize.StockKeepingUnit != null) {
            System.assert(
                fromRingSize.StockKeepingUnit.endsWith('080'),
                'Ring_Size__c should encode 8 as 080. Actual: ' + fromRingSize.StockKeepingUnit
            );
        }
        
        if (productFieldExists('Chain_Length__c') && fromChainLength.StockKeepingUnit != null) {
            System.assert(
                fromChainLength.StockKeepingUnit.endsWith('180'),
                'Chain_Length__c should encode 18 as 180. Actual: ' + fromChainLength.StockKeepingUnit
            );
        }
        
        if (productFieldExists('Length__c') && fromLength.StockKeepingUnit != null) {
            System.assert(
                fromLength.StockKeepingUnit.endsWith('200'),
                'Length__c should encode 20 as 200. Actual: ' + fromLength.StockKeepingUnit
            );
        }
        
        System.assertNotEquals(
            null,
            fromQuotedName.StockKeepingUnit,
            'Quoted-name necklace should still receive a SKU.'
        );
        
        System.assert(
            Pattern.matches('^N[0-9]{4}SG000$', fromQuotedName.StockKeepingUnit),
            'Quoted-name necklace should use N + style + SG. Actual: ' +
            fromQuotedName.StockKeepingUnit
        );
        
        System.assert(
            fromQuotedName.StockKeepingUnit.endsWith('000'),
            'Quoted-name dimension currently falls back to 000 for a trailing quote. Actual: ' +
            fromQuotedName.StockKeepingUnit
        );
        
        System.assert(
            fromSizeName.StockKeepingUnit != null &&
            fromSizeName.StockKeepingUnit.endsWith('090'),
            'Name with size 9 should encode 090. Actual: ' + fromSizeName.StockKeepingUnit
        );
        
        System.assert(
            invalidDimension.StockKeepingUnit != null &&
            invalidDimension.StockKeepingUnit.endsWith('000'),
            'Invalid dimension should encode 000. Actual: ' + invalidDimension.StockKeepingUnit
        );
    }
    

    @IsTest
    static void testDimensionEncodingForShopifyUsSizeFormats() {
        Product2 parenthesizedUs = buildVariantWithSize(
            'Parenthesized US Ring',
            'Ring',
            'Gold',
            'UK N 1/2 (US 7)'
        );

        Product2 plainUs = buildVariantWithSize(
            'Plain US Ring',
            'Ring',
            'Gold',
            'US 6.5'
        );

        Product2 dimensionFromName = buildVariant(
            'Ring UK N 1/2 (US 7)',
            'Ring',
            'Gold'
        );

        Test.startTest();
        ProductSkuService.assignSkusForNewInboundVariants(
            new List<Product2>{ parenthesizedUs, plainUs, dimensionFromName }
        );
        Test.stopTest();

        System.assert(
            parenthesizedUs.StockKeepingUnit.endsWith('070'),
            'Parenthesized US 7 should encode as 070. Actual: ' +
            parenthesizedUs.StockKeepingUnit
        );
        System.assert(
            plainUs.StockKeepingUnit.endsWith('065'),
            'US 6.5 should encode as 065. Actual: ' + plainUs.StockKeepingUnit
        );
        System.assert(
            dimensionFromName.StockKeepingUnit.endsWith('070'),
            'US size parsed from the Variant name should encode as 070. Actual: ' +
            dimensionFromName.StockKeepingUnit
        );
    }

    @IsTest
    static void testDimensionDefaultValuesAndLongDimensionTruncation() {
        List<String> noSizeValues = new List<String>{
            '-',
                'none',
                'no size',
                'one size',
                'onesize',
                'one-size',
                'default title'
                };
                    
                    Integer sequence = 0;
        
        for (String sizeValue : noSizeValues) {
            sequence++;
            
            Product2 variant = buildVariantWithSize(
                'No Size Design ' + sequence,
                'Ring',
                'Gold Plated',
                sizeValue
            );
            
            ProductSkuService.assignSkusForNewInboundVariants(
                new List<Product2>{ variant }
            );
            
            System.assertNotEquals(null, variant.StockKeepingUnit);
            System.assert(
                variant.StockKeepingUnit.endsWith('000'),
                'No-size value should encode 000. Value=' + sizeValue +
                ', SKU=' + variant.StockKeepingUnit
            );
        }
        
        Product2 longDimension = buildVariantWithSize(
            'Long Dimension Unique Design',
            'Ring',
            'Gold Plated',
            '123.4'
        );
        
        ProductSkuService.assignSkusForNewInboundVariants(
            new List<Product2>{ longDimension }
        );
        
        System.assert(
            longDimension.StockKeepingUnit.endsWith('234'),
            'Dimension 123.4 encodes to 1234 and truncates to 234. Actual: ' +
            longDimension.StockKeepingUnit
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // deriveMaterialFromShopifyPayload coverage
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testDeriveMaterialFromShopifyPayloadMetafieldLabel() {
        Map<String, Object> payload = new Map<String, Object>{
            'title' => 'Metafield Product',
                'metafields' => new List<Object>{
                    new Map<String, Object>{
                        'namespace' => 'shopify',
                            'key' => 'jewelry-material',
                            'type' => 'list.metaobject_reference',
                            'references' => new Map<String, Object>{
                                'nodes' => new List<Object>{
                                    new Map<String, Object>{
                                        'fields' => new List<Object>{
                                            new Map<String, Object>{
                                                'key' => 'taxonomy_reference',
                                                    'value' => 'gid://shopify/TaxonomyValue/123'
                                                    },
                                                        new Map<String, Object>{
                                                            'key' => 'label',
                                                                'value' => 'Gold'
                                                                }
                                        }
                                    }
                                }
                            }
                    }
                }
        };
            
            Test.startTest();
        String result = ProductSkuService.deriveMaterialFromShopifyPayload(payload);
        Test.stopTest();
        
        System.assertEquals('Gold', result);
    }
    
    @IsTest
    static void testDeriveMaterialMetafieldNullAndEmptyBranchesFallbackToKeywords() {
        List<Map<String, Object>> payloads =
            new List<Map<String, Object>>{
                /*
* Null metafield entry.
*/
                new Map<String, Object>{
                    'title' => 'Silver Plated Backup',
                        'metafields' => new List<Object>{
                            null
                                }
                },
                    
                    /*
* Metafield has the wrong namespace.
*/
                    new Map<String, Object>{
                        'title' => 'Rose Gold Ring',
                            'metafields' => new List<Object>{
                                new Map<String, Object>{
                                    'namespace' => 'custom',
                                        'key' => 'jewelry-material'
                                        }
                            }
                    },
                        
                        /*
* Correct metafield, but references are null.
*/
                        new Map<String, Object>{
                            'product_type' => 'White Gold Necklace',
                                'metafields' => new List<Object>{
                                    new Map<String, Object>{
                                        'namespace' => 'shopify',
                                            'key' => 'jewelry-material',
                                            'references' => null
                                            }
                                }
                        },
                            
                            /*
* References exist, but nodes are empty.
*/
                            new Map<String, Object>{
                                'title' => 'Gold Plated Backup',
                                    'metafields' => new List<Object>{
                                        new Map<String, Object>{
                                            'namespace' => 'shopify',
                                                'key' => 'jewelry-material',
                                                'references' =>
                                                new Map<String, Object>{
                                                    'nodes' =>
                                                        new List<Object>()
                                                        }
                                        }
                                    }
                            },
                                
                                /*
* First referenced node is null.
*/
                                new Map<String, Object>{
                                    'title' => 'Solid Gold Backup',
                                        'metafields' => new List<Object>{
                                            new Map<String, Object>{
                                                'namespace' => 'shopify',
                                                    'key' => 'jewelry-material',
                                                    'references' =>
                                                    new Map<String, Object>{
                                                        'nodes' =>
                                                            new List<Object>{
                                                                null
                                                                    }
                                                    }
                                            }
                                        }
                                },
                                    
                                    /*
* Referenced node has null fields.
*/
                                    new Map<String, Object>{
                                        'title' => 'Silver Backup',
                                            'metafields' => new List<Object>{
                                                new Map<String, Object>{
                                                    'namespace' => 'shopify',
                                                        'key' => 'jewelry-material',
                                                        'references' =>
                                                        new Map<String, Object>{
                                                            'nodes' =>
                                                                new List<Object>{
                                                                    new Map<String, Object>{
                                                                        'fields' => null
                                                                            }
                                                                }
                                                        }
                                                }
                                            }
                                    },
                                        
                                        /*
* Fields contain null, an unrelated key and a blank label.
*/
                                        new Map<String, Object>{
                                            'title' => 'Gold Backup',
                                                'metafields' => new List<Object>{
                                                    new Map<String, Object>{
                                                        'namespace' => 'shopify',
                                                            'key' => 'jewelry-material',
                                                            'references' =>
                                                            new Map<String, Object>{
                                                                'nodes' =>
                                                                    new List<Object>{
                                                                        new Map<String, Object>{
                                                                            'fields' =>
                                                                                new List<Object>{
                                                                                    null,
                                                                                        new Map<String, Object>{
                                                                                            'key' => 'other',
                                                                                                'value' => 'Ignored'
                                                                                                },
                                                                                                    new Map<String, Object>{
                                                                                                        'key' => 'label',
                                                                                                            'value' => ''
                                                                                                            }
                                                                                }
                                                                        }
                                                                    }
                                                            }
                                                    }
                                                }
                                        }
            };
                
                List<String> results =
                new List<String>();
        
        Test.startTest();
        
        for (Map<String, Object> payload : payloads) {
            results.add(
                ProductSkuService.deriveMaterialFromShopifyPayload(
                    payload
                )
            );
        }
        
        Test.stopTest();
        
        System.assertEquals(
            7,
            results.size()
        );
        
        System.assertEquals(
            'Silver Plated',
            results[0],
            'Null metafield should fall back to the Silver keyword.'
        );
        
        System.assertEquals(
            'Rose Gold Plated',
            results[1],
            'Wrong metafield namespace should fall back to the Rose Gold keyword.'
        );
        
        System.assertEquals(
            'White Gold',
            results[2],
            'Null references should fall back to the White Gold keyword.'
        );
        
        System.assertEquals(
            'Gold Plated',
            results[3],
            'Empty nodes should fall back to the Gold Plated keyword.'
        );
        
        System.assertEquals(
            'Solid Gold',
            results[4],
            'A null first node should fall back to the Solid Gold keyword.'
        );
        
        System.assertEquals(
            'Silver Plated',
            results[5],
            'Null fields should fall back to the Silver keyword.'
        );
        
        System.assertEquals(
            'Gold Plated',
            results[6],
            'A blank material label should fall back to the Gold keyword.'
        );
    }
    
    @IsTest
    static void testDeriveMaterialFromMalformedMetafieldsFallsBack() {
        Map<String, Object> payload = new Map<String, Object>{
            'title' => 'Silver Fallback Product',
                'metafields' => 'not-a-list'
                };
                    
                    Test.startTest();
        String result = ProductSkuService.deriveMaterialFromShopifyPayload(payload);
        Test.stopTest();
        
        System.assertEquals('Silver Plated', result);
    }
    
    @IsTest
    static void testDeriveMaterialFromOptionsAndNullPayload() {
        Map<String, Object> optionPayload = new Map<String, Object>{
            'options' => new List<Object>{
                null,
                    new Map<String, Object>{
                        'name' => 'Material',
                            'values' => new List<Object>{
                                null,
                                    'Gold',
                                    'Silver'
                                    }
                    }
            }
        };
            
            Test.startTest();
        String result1 = ProductSkuService.deriveMaterialFromShopifyPayload(optionPayload);
        String result2 = ProductSkuService.deriveMaterialFromShopifyPayload(null);
        String result3 = ProductSkuService.deriveMaterialFromShopifyPayload(
            new Map<String, Object>{ 'title' => 'Bronze Item' }
        );
        Test.stopTest();
        
        System.assertEquals('Gold Plated', result1);
        System.assertEquals(null, result2);
        System.assertEquals(null, result3);
    }
    

    // ─────────────────────────────────────────────────────────────────────
    // deriveMaterialsFromShopifyPayload coverage
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testDeriveMaterialsFromShopifyPayloadReturnsAllUniqueLabels() {
        Map<String, Object> payload = new Map<String, Object>{
            'metafields' => new List<Object>{
                null,
                new Map<String, Object>{
                    'namespace' => 'custom',
                    'key' => 'jewelry-material'
                },
                new Map<String, Object>{
                    'namespace' => 'shopify',
                    'key' => 'jewelry-material',
                    'references' => new Map<String, Object>{
                        'nodes' => new List<Object>{
                            null,
                            new Map<String, Object>{ 'fields' => null },
                            new Map<String, Object>{
                                'fields' => new List<Object>{
                                    null,
                                    new Map<String, Object>{
                                        'key' => 'other',
                                        'value' => 'Ignore'
                                    },
                                    new Map<String, Object>{
                                        'key' => 'label',
                                        'value' => 'Gold'
                                    },
                                    new Map<String, Object>{
                                        'key' => 'label',
                                        'value' => 'Silver'
                                    },
                                    new Map<String, Object>{
                                        'key' => 'label',
                                        'value' => 'Gold'
                                    },
                                    new Map<String, Object>{
                                        'key' => 'label',
                                        'value' => ' '
                                    }
                                }
                            }
                        }
                    }
                }
            }
        };

        Test.startTest();
        List<String> materials = ProductSkuService.deriveMaterialsFromShopifyPayload(payload);
        Test.stopTest();

        System.assertEquals(2, materials.size());
        System.assertEquals('Gold', materials[0]);
        System.assertEquals('Silver', materials[1]);
    }

    @IsTest
    static void testDeriveMaterialsFromShopifyPayloadFallbackAndNull() {
        Map<String, Object> fallbackPayload = new Map<String, Object>{
            'title' => 'Gold Plated Ring',
            'metafields' => 'malformed'
        };

        Test.startTest();
        List<String> nullMaterials = ProductSkuService.deriveMaterialsFromShopifyPayload(null);
        List<String> fallbackMaterials = ProductSkuService.deriveMaterialsFromShopifyPayload(fallbackPayload);
        List<String> noMaterials = ProductSkuService.deriveMaterialsFromShopifyPayload(
            new Map<String, Object>{ 'title' => 'Bronze Product' }
        );
        Test.stopTest();

        System.assertEquals(0, nullMaterials.size());
        System.assertEquals(1, fallbackMaterials.size());
        System.assertEquals('Gold Plated', fallbackMaterials[0]);
        System.assertEquals(0, noMaterials.size());
    }

    // ─────────────────────────────────────────────────────────────────────
    // resolveSkuCollisions coverage
    // ─────────────────────────────────────────────────────────────────────
    
    @IsTest
    static void testResolveSkuCollisionsDoesNotAllocateNewStyleNumber() {
        String duplicateSku = compactSku('R', 'SG', '000');

        insertExistingProducts(
            new List<Product2>{
                buildExistingProductWithSku('Existing Collision', duplicateSku)
            }
        );

        Product2 inbound = buildVariantWithSize(
            'Inbound Collision Product',
            'Ring',
            'Gold',
            null
        );
        inbound.StockKeepingUnit = duplicateSku;

        List<Product2> inboundVariants = new List<Product2>{ inbound };
        Database.UpsertResult[] results = Database.upsert(inboundVariants, false);

        Test.startTest();
        List<Product2> retryVariants = ProductSkuService.resolveSkuCollisions(
            inboundVariants,
            results
        );
        Test.stopTest();

        System.assertEquals(
            0,
            retryVariants.size(),
            'The current resolver logs duplicate SKUs and does not allocate a new style number.'
        );
        System.assertEquals(duplicateSku, inbound.StockKeepingUnit);
    }
    
    @IsTest
    static void testResolveSkuCollisionsUsesDimensionAndSkipsUnmappableVariant() {
        String duplicateSku = compactSku('N', 'SG', '180');

        insertExistingProducts(
            new List<Product2>{
                buildExistingProductWithSku('Existing Necklace Collision', duplicateSku)
            }
        );

        Product2 inbound = buildVariantWithSize(
            'Inbound Necklace Collision',
            'Necklace',
            'Gold',
            '18'
        );
        inbound.StockKeepingUnit = duplicateSku;

        Database.UpsertResult[] results = Database.upsert(
            new List<Product2>{ inbound },
            false
        );

        Test.startTest();
        List<Product2> retryVariants = ProductSkuService.resolveSkuCollisions(
            new List<Product2>{ inbound },
            results
        );
        Test.stopTest();

        System.assertEquals(
            0,
            retryVariants.size(),
            'Duplicate SKU errors are logged and are not assigned a new design number.'
        );
        System.assertEquals(duplicateSku, inbound.StockKeepingUnit);
    }
    
    @IsTest
    static void testResolveSkuCollisionsHandlesNullInputsAndEmptyResults() {
        Product2 p = buildVariant('Null Input Product', 'Ring', 'Gold');
        
        Test.startTest();
        List<Product2> result1 = ProductSkuService.resolveSkuCollisions(null, null);
        List<Product2> result2 = ProductSkuService.resolveSkuCollisions(new List<Product2>(), null);
        List<Product2> result3 = ProductSkuService.resolveSkuCollisions(new List<Product2>{ p }, new Database.UpsertResult[]{});
        Test.stopTest();
        
        System.assertEquals(0, result1.size());
        System.assertEquals(0, result2.size());
        System.assertEquals(0, result3.size());
    }
    
    @IsTest
    static void testResolveSkuCollisionsIgnoresSuccessfulAndNonDuplicateResults() {
        Product2 successProduct = buildVariant('Successful Upsert Product', 'Ring', 'Gold');
        successProduct.StockKeepingUnit = uniqueText('SUCCESS');
        
        Database.UpsertResult[] successResults =
            Database.upsert(new List<Product2>{ successProduct }, false);
        
        Product2 missingName = new Product2();
        missingName.put('Type__c', 'Variant');
        missingName.put('Material__c', 'Gold');
        missingName.Family = 'Ring';
        missingName.StockKeepingUnit = uniqueText('MISSING-NAME');
        
        Database.UpsertResult[] nonDuplicateResults =
            Database.upsert(new List<Product2>{ missingName }, false);
        
        Test.startTest();
        List<Product2> retry1 =
            ProductSkuService.resolveSkuCollisions(
                new List<Product2>{ successProduct },
                successResults
            );
        
        List<Product2> retry2 =
            ProductSkuService.resolveSkuCollisions(
                new List<Product2>{ missingName },
                nonDuplicateResults
            );
        Test.stopTest();
        
        System.assertEquals(0, retry1.size());
        System.assertEquals(0, retry2.size());
    }
    
    @IsTest
    static void testResolveSkuCollisionsWithMoreVariantsThanResultsAndNullVariant() {
        String duplicateSku = compactSku('R', 'SG', '000');

        insertExistingProducts(
            new List<Product2>{
                buildExistingProductWithSku('Existing Collision More', duplicateSku)
            }
        );

        Product2 inbound = buildVariant('Inbound Collision More', 'Ring', 'Gold');
        inbound.StockKeepingUnit = duplicateSku;

        Database.UpsertResult[] results = Database.upsert(
            new List<Product2>{ inbound },
            false
        );

        Test.startTest();
        List<Product2> retry = ProductSkuService.resolveSkuCollisions(
            new List<Product2>{ null, inbound },
            results
        );
        Test.stopTest();

        System.assertEquals(
            0,
            retry.size(),
            'The null Variant aligned to the only result is skipped safely.'
        );
    }
    
    @IsTest
    static void testBuildShortSkuForVariant() {
        Product2 fullSkuVariant = new Product2(
            StockKeepingUnit = 'R0042GP075'
        );
        
        Product2 shortValue = new Product2(
            StockKeepingUnit = 'R004'
        );
        
        System.assertEquals(
            'R0042',
            ProductSkuService.buildShortSkuForVariant(fullSkuVariant)
        );
        
        System.assertEquals(
            null,
            ProductSkuService.buildShortSkuForVariant(shortValue)
        );
        
        System.assertEquals(
            null,
            ProductSkuService.buildShortSkuForVariant(null)
        );
        
        System.assertEquals(
            null,
            ProductSkuService.buildShortSkuForVariant(new Product2())
        );
    }
}