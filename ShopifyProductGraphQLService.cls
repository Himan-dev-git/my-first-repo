public with sharing class ShopifyProductGraphQLService {
    
    @future(callout=true)
    public static void syncProductsAsync(List<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) return;
        
        List<Product2> products = [
            SELECT Id, Name, Family, Description, IsActive, Type__c,
            Shop_Id__c, StockKeepingUnit, Updated_by_Integration__c,
            Parent__c, Parent__r.Shop_Id__c
            FROM   Product2
            WHERE  Id IN :productIds
        ];
        
        /*
* TEMPORARILY DISABLED:
* General Salesforce -> Shopify product synchronization.
*
* This prevents Salesforce from creating or updating Shopify product
* title, description, status, product type, or variants through the
* normal Product2 outbound synchronization path.
*
* SKU-only writeback methods remain enabled below.
*/
        /*
for (Product2 p : products) {
if (p.Type__c == 'Variant') {
syncSingleVariant(p);
} else {
syncSingleProduct(p);
}
}
*/
        
        System.debug(
            LoggingLevel.WARN,
            'ShopifyProductGraphQLService.syncProductsAsync: General Salesforce to Shopify product sync is temporarily disabled. SKU-only writeback remains enabled.'
        );
    }
    
    private static void syncSingleProduct(Product2 p) {
        if (p == null) return;
        if (String.isBlank(p.Shop_Id__c)) {
            createSingleProduct(p);
        } else {
            updateSingleProduct(p);
        }
    }
    
    private static void createSingleProduct(Product2 p) {
        String mutation =
            'mutation productCreate($input: ProductInput!) {' +
            '  productCreate(input: $input) {' +
            '    product { id title status productType legacyResourceId }' +
            '    userErrors { field message }' +
            '  }' +
            '}';
        
        Map<String, Object> input = new Map<String, Object>{
            'title'  => p.Name,
                'status' => p.IsActive ? 'ACTIVE' : 'DRAFT'
                    };
                        if (!String.isBlank(p.Family))      input.put('productType',    p.Family);
        if (!String.isBlank(p.Description)) input.put('descriptionHtml', p.Description);
        
        Map<String, Object> response = ShopifyGraphQLHelper.execute(
            mutation, new Map<String, Object>{ 'input' => input }
        );
        
        validateUserErrors(response, 'productCreate');
        
        Map<String, Object> data    = (Map<String, Object>) response.get('data');
        Map<String, Object> result  = (Map<String, Object>) data.get('productCreate');
        Map<String, Object> product = (Map<String, Object>) result.get('product');
        
        if (product != null && product.get('legacyResourceId') != null) {
            update new Product2(
                Id         = p.Id,
                Shop_Id__c = String.valueOf(product.get('legacyResourceId'))
            );
        }
    }
    
    private static void updateSingleProduct(Product2 p) {
        String mutation =
            'mutation productUpdate($input: ProductUpdateInput!) {' +
            '  productUpdate(product: $input) {' +
            '    product { id title status productType }' +
            '    userErrors { field message }' +
            '  }' +
            '}';
        
        Map<String, Object> input = new Map<String, Object>{
            'id'     => ShopifyGraphQLHelper.toProductGid(p.Shop_Id__c),
                'title'  => p.Name,
                'status' => p.IsActive ? 'ACTIVE' : 'DRAFT'
                    };
                        if (!String.isBlank(p.Family))      input.put('productType',    p.Family);
        if (!String.isBlank(p.Description)) input.put('descriptionHtml', p.Description);
        
        Map<String, Object> response = ShopifyGraphQLHelper.execute(
            mutation, new Map<String, Object>{ 'input' => input }
        );
        validateUserErrors(response, 'productUpdate');
    }
    
    private static void syncSingleVariant(Product2 v) {
        if (v == null || String.isBlank(v.Shop_Id__c)) return;
        if (v.Parent__c == null && (v.Parent__r == null || String.isBlank(v.Parent__r.Shop_Id__c))) return;
        
        String productShopId = (v.Parent__r != null) ? v.Parent__r.Shop_Id__c : null;
        if (String.isBlank(productShopId) && v.Parent__c != null) {
            Product2 parentRow = [SELECT Shop_Id__c FROM Product2 WHERE Id = :v.Parent__c LIMIT 1];
            productShopId = parentRow.Shop_Id__c;
        }
        if (String.isBlank(productShopId)) return;
        
        String mutation =
            'mutation productVariantsBulkUpdate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {' +
            '  productVariantsBulkUpdate(productId: $productId, variants: $variants) {' +
            '    product { id }' +
            '    productVariants { id title sku }' +
            '    userErrors { field message }' +
            '  }' +
            '}';
        
        Map<String, Object> variantInput = new Map<String, Object>{
            'id'            => ShopifyGraphQLHelper.toVariantGid(v.Shop_Id__c),
                'inventoryItem' => new Map<String, Object>{ 'sku' => v.StockKeepingUnit }
        };
            
            Map<String, Object> response = ShopifyGraphQLHelper.execute(
                mutation,
                new Map<String, Object>{
                    'productId' => ShopifyGraphQLHelper.toProductGid(productShopId),
                        'variants'  => new List<Object>{ variantInput }
                }
            );
        validateUserErrors(response, 'productVariantsBulkUpdate');
    }
    
    // ── EXISTING: unchanged ───────────────────────────────────────────────────
    
    @future(callout=true)
    public static void syncVariantSkuOnlyAsync(List<Id> variantIds) {
        if (variantIds == null || variantIds.isEmpty()) return;
        
        List<Product2> sfVariants = [
            SELECT Id, Shop_Id__c, StockKeepingUnit, Parent__c, Parent__r.Shop_Id__c
            FROM   Product2
            WHERE  Id IN :variantIds
        ];
        
        for (Product2 v : sfVariants) {
            if (String.isBlank(v.Shop_Id__c))         continue;
            if (String.isBlank(v.StockKeepingUnit))   continue;
            if (v.Parent__r == null || String.isBlank(v.Parent__r.Shop_Id__c)) continue;
            
            String mutation =
                'mutation productVariantsBulkUpdate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {' +
                '  productVariantsBulkUpdate(productId: $productId, variants: $variants) {' +
                '    product { id }' +
                '    productVariants { id title sku }' +
                '    userErrors { field message }' +
                '  }' +
                '}';
            
            Map<String, Object> variantInput = new Map<String, Object>{
                'id'            => ShopifyGraphQLHelper.toVariantGid(v.Shop_Id__c),
                    'inventoryItem' => new Map<String, Object>{ 'sku' => v.StockKeepingUnit }
            };
                
                Map<String, Object> response = ShopifyGraphQLHelper.execute(
                    mutation,
                    new Map<String, Object>{
                        'productId' => ShopifyGraphQLHelper.toProductGid(v.Parent__r.Shop_Id__c),
                            'variants'  => new List<Object>{ variantInput }
                    }
                );
            validateUserErrors(response, 'productVariantsBulkUpdate');
        }
    }
    
    // ── CHANGED: syncVariantWeightAsync ──────────────────────────────────────
    //
    // Now also fetches the product-level jewelry-material metafield
    // (namespace: "shopify", key: "jewelry-material") in the same GraphQL call
    // and writes the primary material label to Material__c on the variant Product2.
    // jewelry-material is a list.metaobject_reference — multiple materials are
    // supported in Shopify but we pick the first node (primary material) only.
    //
    // The inventoryItem query traverses up to the parent product metafield —
    // no extra callout, no extra SOQL.
    // ─────────────────────────────────────────────────────────────────────────
    
    @future(callout=true)
    public static void syncVariantWeightAsync(List<Id> variantIds) {
        if (variantIds == null || variantIds.isEmpty()) return;
        
        List<Product2> variants = [
            SELECT Id, Shop_Id__c, Inventory_Item_Id__c,
            StockKeepingUnit, Family, Material__c,
            Parent__c, Parent__r.Shop_Id__c
            FROM   Product2
            WHERE  Id IN :variantIds
            AND    Inventory_Item_Id__c != null
        ];
        
        if (variants.isEmpty()) return;
        
        List<Product2> toUpdate = new List<Product2>();
        
        for (Product2 v : variants) {
            Decimal weightValue = null;
            String  weightUnit  = null;
            
            // ── CHANGED: query now also fetches the jewelry-material metafield
            //    from the parent product in the same round-trip.
            //    namespace "shopify", key "jewelry-material" is Shopify's
            //    built-in metafield for the product Material field.
            //    It is a list.metaobject_reference — we fetch references.nodes
            //    so we can read the label field from each metaobject.
            //    Multiple materials are supported; we pick the first node only.
            String query =
                'query getInventoryIt($id: ID!) {' +
                '  inventoryItem(id: $id) {' +
                '    measurement {' +
                '      weight {' +
                '        value' +
                '        unit' +
                '      }' +
                '    }' +
                '    variant {' +
                '      product {' +
                '        metafield(namespace: "shopify", key: "jewelry-material") {' +
                '          references(first: 1) {' +
                '            nodes {' +
                '              ... on Metaobject {' +
                '                fields {' +
                '                  key' +
                '                  value' +
                '                }' +
                '              }' +
                '            }' +
                '          }' +
                '        }' +
                '      }' +
                '    }' +
                '  }' +
                '}';
            
            Map<String, Object> variables = new Map<String, Object>{
                'id' => 'gid://shopify/InventoryItem/' + v.Inventory_Item_Id__c
                    };
                        
                        Map<String, Object> response;
            try {
                response = ShopifyGraphQLHelper.execute(query, variables);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                             'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                             'GraphQL call failed for variant ' + v.Shop_Id__c +
                             ' inventoryItemId=' + v.Inventory_Item_Id__c +
                             ': ' + e.getMessage());
                continue;
            }
            
            if (response == null || !response.containsKey('data')) continue;
            
            Map<String, Object> data = (Map<String, Object>) response.get('data');
            if (data == null) continue;
            
            Map<String, Object> inventoryItem = (Map<String, Object>) data.get('inventoryItem');
            if (inventoryItem == null) continue;
            
            // ── Weight parsing — unchanged logic ─────────────────────────
            Map<String, Object> measurement = (Map<String, Object>) inventoryItem.get('measurement');
            if (measurement != null) {
                Map<String, Object> weight = (Map<String, Object>) measurement.get('weight');
                if (weight != null) {
                    Object rawValue = weight.get('value');
                    Object rawUnit  = weight.get('unit');
                    
                    if (rawValue != null) {
                        try {
                            weightValue = Decimal.valueOf(String.valueOf(rawValue));
                        } catch (Exception e) {
                            System.debug(LoggingLevel.WARN,
                                         'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                                         'Could not parse weight value "' + rawValue + '" for variant ' +
                                         v.Shop_Id__c);
                        }
                        
                        if (weightValue != null && weightValue <= 0) {
                            System.debug(LoggingLevel.INFO,
                                         'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                                         'Shopify returned zero weight for variant ' + v.Shop_Id__c +
                                         ' — skipping weight update.');
                            weightValue = null;
                        }
                        
                        if (weightValue != null && rawUnit != null) {
                            weightUnit = normaliseWeightUnit(String.valueOf(rawUnit));
                        }
                    }
                }
            }
            
            // ── CHANGED: material metafield parsing ───────────────────────
            // jewelry-material is a list.metaobject_reference.
            // Response structure:
            //   metafield.references.nodes[0].fields[] → find key="label" → value
            // Multiple materials are possible (Gold + Pearl etc.) —
            // we pick the FIRST node only so the SKU prefix is deterministic.
            String materialValue = null;
            try {
                Map<String, Object> variant = (Map<String, Object>) inventoryItem.get('variant');
                if (variant != null) {
                    Map<String, Object> product = (Map<String, Object>) variant.get('product');
                    if (product != null) {
                        Map<String, Object> metafield = (Map<String, Object>) product.get('metafield');
                        if (metafield != null) {
                            Map<String, Object> references = (Map<String, Object>) metafield.get('references');
                            if (references != null) {
                                List<Object> nodes = (List<Object>) references.get('nodes');
                                if (nodes != null && !nodes.isEmpty()) {
                                    // First node = primary material
                                    Map<String, Object> firstNode = (Map<String, Object>) nodes[0];
                                    if (firstNode != null) {
                                        List<Object> fields = (List<Object>) firstNode.get('fields');
                                        if (fields != null) {
                                            for (Object fieldObj : fields) {
                                                Map<String, Object> field = (Map<String, Object>) fieldObj;
                                                if (field != null &&
                                                    String.valueOf(field.get('key')) == 'label' &&
                                                    field.get('value') != null) {
                                                        materialValue = String.valueOf(field.get('value'));
                                                        break;
                                                    }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                             'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                             'Could not parse material metafield for variant ' + v.Shop_Id__c +
                             ': ' + e.getMessage());
            }
            
            // ── Build update record — only include fields that have a value ─
            if (weightValue == null && String.isBlank(materialValue)) {
                continue; // nothing to write
            }
            
            Product2 upd = new Product2(Id = v.Id);
            
            if (weightValue != null) {
                upd.Weight__c      = weightValue;
                upd.Weight_Unit__c = weightUnit;
                System.debug(LoggingLevel.INFO,
                             'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                             'Variant ' + v.Shop_Id__c + ' weight=' + weightValue +
                             ' unit=' + weightUnit);
            }
            
            if (!String.isBlank(materialValue)) {
                upd.Material__c = materialValue;
                System.debug(LoggingLevel.INFO,
                             'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                             'Variant ' + v.Shop_Id__c + ' material=' + materialValue);
            }
            
            toUpdate.add(upd);
        }
        
        if (!toUpdate.isEmpty()) {
            try {
                update toUpdate;
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                             'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                             'DML error updating Weight__c/Weight_Unit__c/Material__c: ' + e.getMessage());
            }
        }
        
        // ── SKU generation + Shopify writeback ────────────────────────────────
        // For variants where Material__c was just resolved but StockKeepingUnit
        // is still blank, generate a SKU now and write it back to both
        // Salesforce and Shopify.
        //
        // We build a temporary Product2 list that matches what
        // ProductSkuService.assignSkusForNewInboundVariants expects:
        //   Type__c = 'Variant', Family populated, Material__c populated,
        //   StockKeepingUnit blank.
        //
        // After SKU assignment we update Salesforce first, then push to Shopify
        // using the same productVariantsBulkUpdate mutation as syncVariantSkuOnlyAsync.
        // ─────────────────────────────────────────────────────────────────────
        
        // Re-query so we have the freshly written Material__c values
        // (the toUpdate list only carries the fields we SET, not the full record)
        List<Id> updatedIds = new List<Id>();
        for (Product2 upd : toUpdate) {
            updatedIds.add(upd.Id);
        }
        
        if (updatedIds.isEmpty()) return;
        
        Set<String> productFields = Product2.SObjectType.getDescribe().fields.getMap().keySet();
        
        List<String> selectFields = new List<String>{
            'Id',
                'Shop_Id__c',
                'StockKeepingUnit',
                'Family',
                'Material__c',
                'Type__c',
                'Parent__c',
                'Size__c',
                'Parent__r.Shop_Id__c'
                };
                    
                    List<String> optionalSkuFields = new List<String>{
                        'Size__c',
                            'Dimension__c',
                            'Ring_Size__c',
                            'Chain_Length__c',
                            'Length__c',
                            'Product_Type__c',
                            'Type_Code__c',
                            'Metal_Colour__c',
                            'Size__c',
                            'Metal_Color__c'
                            };
                                
                                for (String fieldName : optionalSkuFields) {
                                    if (productFields.contains(fieldName)) {
                                        selectFields.add(fieldName);
                                    }
                                }
        
        String freshVariantQuery =
            'SELECT ' + String.join(selectFields, ',') +
            ' FROM Product2' +
            ' WHERE Id IN :updatedIds' +
            ' AND (StockKeepingUnit = null OR StockKeepingUnit = \'\')';
        
        List<Product2> freshVariants = Database.query(freshVariantQuery);        
        if (freshVariants.isEmpty()) return;
        
        // Only process variants that now have Material__c (just written above)
        List<Product2> eligibleForSku = new List<Product2>();
        for (Product2 fv : freshVariants) {
            if (!String.isBlank(fv.Material__c)) {
                fv.Type__c = 'Variant'; // ensure service picks them up
                eligibleForSku.add(fv);
            }
        }
        
        if (eligibleForSku.isEmpty()) return;
        
        // Assign SKUs using the same logic as the initial product creation flow
        ProductSkuService.assignSkusForNewInboundVariants(eligibleForSku);
        
        // Collect only those that actually got a SKU assigned
        List<Product2> skuAssigned = new List<Product2>();
        for (Product2 ev : eligibleForSku) {
            if (!String.isBlank(ev.StockKeepingUnit)) {
                skuAssigned.add(ev);
            }
        }
        
        if (skuAssigned.isEmpty()) return;
        
        // Write the new SKU back to Salesforce
        try {
            update skuAssigned;
            System.debug(LoggingLevel.INFO,
                         'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                         'SKU writeback to Salesforce complete for ' + skuAssigned.size() + ' variant(s).');
            
            List<Id> skuAssignedIds = new List<Id>();
            
            for (Product2 sv : skuAssigned) {
                skuAssignedIds.add(sv.Id);
            }
            
            if (!skuAssignedIds.isEmpty()) {
                System.enqueueJob(new ShopifySkuWritebackQueueable(skuAssignedIds));
            }
            
        } catch (DmlException e) {
            Boolean isDuplicateSku = false;
            
            for (Integer i = 0; i < e.getNumDml(); i++) {
                if (String.valueOf(e.getDmlStatusCode(i)) == 'DUPLICATE_VALUE' &&
                    e.getDmlMessage(i) != null &&
                    e.getDmlMessage(i).toLowerCase().contains('sku')) {
                        isDuplicateSku = true;
                        break;
                    }
            }
            
            if (!isDuplicateSku) {
                System.debug(LoggingLevel.ERROR,
                             'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                             'DML error writing SKU to Salesforce: ' + e.getMessage());
                return;
            }
            
            System.debug(LoggingLevel.WARN,
                         'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                         'Duplicate SKU detected while writing to Salesforce. Re-generating SKU and retrying once. Error: ' +
                         e.getMessage());
            
            for (Product2 sv : skuAssigned) {
                sv.StockKeepingUnit = null;
                sv.Type__c = 'Variant';
            }
            
            ProductSkuService.assignSkusForNewInboundVariants(skuAssigned);
            
            try {
                update skuAssigned;
                System.debug(LoggingLevel.INFO,
                             'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                             'SKU writeback retry to Salesforce complete for ' +
                             skuAssigned.size() + ' variant(s).');
            } catch (Exception retryException) {
                System.debug(LoggingLevel.ERROR,
                             'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                             'DML error writing regenerated SKU to Salesforce: ' +
                             retryException.getMessage());
                return;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                         'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                         'DML error writing SKU to Salesforce: ' + e.getMessage());
            return;
        }
        
        // Push the SKU back to Shopify for each variant
        for (Product2 sv : skuAssigned) {
            if (String.isBlank(sv.Shop_Id__c)) continue;
            if (sv.Parent__r == null || String.isBlank(sv.Parent__r.Shop_Id__c)) continue;
            
            String skuMutation =
                'mutation productVariantsBulkUpdate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {' +
                '  productVariantsBulkUpdate(productId: $productId, variants: $variants) {' +
                '    product { id }' +
                '    productVariants { id title sku }' +
                '    userErrors { field message }' +
                '  }' +
                '}';
            
            Map<String, Object> variantInput = new Map<String, Object>{
                'id'            => ShopifyGraphQLHelper.toVariantGid(sv.Shop_Id__c),
                    'inventoryItem' => new Map<String, Object>{ 'sku' => sv.StockKeepingUnit }
            };
                
                try {
                    Map<String, Object> skuResponse = ShopifyGraphQLHelper.execute(
                        skuMutation,
                        new Map<String, Object>{
                            'productId' => ShopifyGraphQLHelper.toProductGid(sv.Parent__r.Shop_Id__c),
                                'variants'  => new List<Object>{ variantInput }
                        }
                    );
                    validateUserErrors(skuResponse, 'productVariantsBulkUpdate');
                    System.debug(LoggingLevel.INFO,
                                 'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                                 'SKU "' + sv.StockKeepingUnit + '" pushed to Shopify for variant ' +
                                 sv.Shop_Id__c);
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR,
                                 'ShopifyProductGraphQLService.syncVariantWeightAsync: ' +
                                 'Failed to push SKU to Shopify for variant ' + sv.Shop_Id__c +
                                 ': ' + e.getMessage());
                }
        }
    }
    
    // Converts Shopify GraphQL unit enum to Salesforce Weight_Unit__c picklist value
    private static String normaliseWeightUnit(String shopifyUnit) {
        if (String.isBlank(shopifyUnit)) return 'g';
        switch on shopifyUnit.toUpperCase() {
            when 'GRAMS'     { return 'g'; }
            when 'KILOGRAMS' { return 'kg'; }
            when 'OUNCES'    { return 'oz'; }
            when 'POUNDS'    { return 'lb'; }
            when else        { return shopifyUnit.toLowerCase(); }
        }
    }
    
    @future(callout=true)
    public static void fetchAndProcessProductForInboundSyncAsync(String shopifyProductId) {
        if (String.isBlank(shopifyProductId)) {
            return;
        }
        
        String numericProductId = extractNumericIdFromAnyShopifyId(shopifyProductId);
        
        if (String.isBlank(numericProductId)) {
            System.debug(
                LoggingLevel.ERROR,
                'fetchAndProcessProductForInboundSyncAsync: Invalid Shopify product id: ' +
                shopifyProductId
            );
            return;
        }
        
        String queryText =
            'query GetProductForSalesforceInbound($id: ID!) {' +
            '  product(id: $id) {' +
            '    id ' +
            '    legacyResourceId ' +
            '    title ' +
            '    handle ' +
            '    descriptionHtml ' +
            '    productType ' +
            '    status ' +
            '    tags ' +
            '    featuredImage { id url } ' +
            '    options(first: 10) { id name values } ' +
            '    images(first: 20) { nodes { id url altText } } ' +
            '    variants(first: 100) { ' +
            '      nodes { ' +
            '        id ' +
            '        legacyResourceId ' +
            '        title ' +
            '        sku ' +
            '        price ' +
            '        inventoryPolicy ' +
            '        selectedOptions { name value } ' +
            '        image { id url } ' +
            '        inventoryItem { ' +
            '          id ' +
            '          legacyResourceId ' +
            '          measurement { weight { value unit } } ' +
            '        } ' +
            '      } ' +
            '    } ' +
            '    sfProductName: metafield(namespace: "test_data", key: "binding_mount") { ' +
            '      namespace key value ' +
            '    } ' +
            '    sfVariants: metafield(namespace: "custom", key: "sf_variants") { ' +
            '      namespace key value ' +
            '      references(first: 20) { ' +
            '        nodes { ' +
            '          ... on Product { id legacyResourceId title } ' +
            '        } ' +
            '      } ' +
            '    } ' +
            '    jewelryMaterial: metafield(namespace: "shopify", key: "jewelry-material") { ' +
            '      namespace key value ' +
            '      references(first: 10) { ' +
            '        nodes { ' +
            '          ... on Metaobject { ' +
            '            fields { key value } ' +
            '          } ' +
            '        } ' +
            '      } ' +
            '    } ' +
            '  } ' +
            '}';
        
        Map<String, Object> responseMap;
        
        try {
            responseMap = ShopifyGraphQLHelper.execute(
                queryText,
                new Map<String, Object>{
                    'id' => 'gid://shopify/Product/' + numericProductId
                        }
            );
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'fetchAndProcessProductForInboundSyncAsync: Shopify GraphQL call failed. ' +
                'ProductId=' + numericProductId +
                ', Error=' + e.getMessage()
            );
            return;
        }
        
        if (responseMap == null || !responseMap.containsKey('data')) {
            System.debug('fetchAndProcessProductForInboundSyncAsync: No data returned.');
            return;
        }
        
        Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
        if (dataMap == null || dataMap.get('product') == null) {
            System.debug(
                'fetchAndProcessProductForInboundSyncAsync: Product not found: ' +
                numericProductId
            );
            return;
        }
        
        Map<String, Object> productNode =
            (Map<String, Object>) dataMap.get('product');
        
        Map<String, Object> restLikeProduct =
            buildRestLikeProductPayloadFromGraphQL(productNode);
        
        ProductOrchestrationService.processProductsFromRestRequest(
            new Map<String, Object>{ 'product' => restLikeProduct },
            new String[]{ 'products', 'variants' }
        );
    }
    
    private static Map<String, Object> buildRestLikeProductPayloadFromGraphQL(
        Map<String, Object> productNode
    ) {
        Map<String, Object> payload = new Map<String, Object>();
        
        if (productNode == null) {
            return payload;
        }
        
        String productId = getLegacyId(productNode);
        
        payload.put('id', productId);
        payload.put('title', productNode.get('title'));
        payload.put('handle', productNode.get('handle'));
        payload.put('body_html', productNode.get('descriptionHtml'));
        payload.put('product_type', productNode.get('productType'));
        
        String status = String.valueOf(productNode.get('status'));
        
        payload.put(
            'status',
            String.isBlank(status)
            ? 'draft'
            : status.toLowerCase()
        );
        
        payload.put(
            'tags',
            joinGraphQLTags(productNode.get('tags'))
        );
        
        /*
* SF Parent Product Name
*
* Shopify GraphQL alias:
*   sfProductName
*
* Shopify metafield:
*   namespace = test_data
*   key       = binding_mount
*
* The value is added directly to the REST-like payload so that
* ProductOrchestrationService can use it while resolving the
* Salesforce parent Product record.
*/
        String sfParentProductName =
            getGraphQLMetafieldValue(productNode, 'sfProductName');
        
        if (!String.isBlank(sfParentProductName)) {
            payload.put(
                'sf_parent_product_name',
                sfParentProductName.trim()
            );
        }
        
        Map<String, Object> featuredImage =
            (Map<String, Object>) productNode.get('featuredImage');
        
        if (
            featuredImage != null &&
            featuredImage.get('url') != null
        ) {
            payload.put(
                'image',
                new Map<String, Object>{
                    'id' => extractNumericIdFromAnyShopifyId(
                        String.valueOf(featuredImage.get('id'))
                    ),
                        'src' => String.valueOf(featuredImage.get('url'))
                        }
            );
        }
        
        List<Object> restImages = new List<Object>();
        
        Map<String, Object> imagesConnection =
            (Map<String, Object>) productNode.get('images');
        
        if (
            imagesConnection != null &&
            imagesConnection.get('nodes') != null
        ) {
            List<Object> imageNodes =
                (List<Object>) imagesConnection.get('nodes');
            
            for (Object imageObj : imageNodes) {
                Map<String, Object> imageNode =
                    (Map<String, Object>) imageObj;
                
                if (imageNode == null) {
                    continue;
                }
                
                restImages.add(
                    new Map<String, Object>{
                        'id' => extractNumericIdFromAnyShopifyId(
                            String.valueOf(imageNode.get('id'))
                        ),
                            'src' => imageNode.get('url'),
                            'alt' => imageNode.get('altText')
                            }
                );
            }
        }
        
        payload.put('images', restImages);
        
        List<Object> restOptions = new List<Object>();
        
        Object rawOptions = productNode.get('options');
        
        if (rawOptions instanceof List<Object>) {
            for (Object optionObj : (List<Object>) rawOptions) {
                Map<String, Object> optionNode =
                    (Map<String, Object>) optionObj;
                
                if (optionNode == null) {
                    continue;
                }
                
                restOptions.add(
                    new Map<String, Object>{
                        'name' => optionNode.get('name'),
                            'values' => optionNode.get('values')
                            }
                );
            }
        } else if (rawOptions instanceof Map<String, Object>) {
            Map<String, Object> optionsConnection =
                (Map<String, Object>) rawOptions;
            
            if (optionsConnection.get('nodes') != null) {
                for (
                    Object optionObj :
                    (List<Object>) optionsConnection.get('nodes')
                ) {
                    Map<String, Object> optionNode =
                        (Map<String, Object>) optionObj;
                    
                    if (optionNode == null) {
                        continue;
                    }
                    
                    restOptions.add(
                        new Map<String, Object>{
                            'name' => optionNode.get('name'),
                                'values' => optionNode.get('values')
                                }
                    );
                }
            }
        }
        
        payload.put('options', restOptions);
        
        /*
* Keep the original metafield structure for existing mapping logic.
*/
        List<Object> restMetafields = new List<Object>();
        
        addSimpleMetafield(
            restMetafields,
            productNode,
            'sfProductName'
        );
        
        addSimpleMetafield(
            restMetafields,
            productNode,
            'sfVariants'
        );
        
        addSimpleMetafield(
            restMetafields,
            productNode,
            'jewelryMaterial'
        );
        
        payload.put('metafields', restMetafields);
        
        List<Object> restVariants = new List<Object>();
        
        Map<String, Object> variantsConnection =
            (Map<String, Object>) productNode.get('variants');
        
        if (
            variantsConnection != null &&
            variantsConnection.get('nodes') != null
        ) {
            List<Object> variantNodes =
                (List<Object>) variantsConnection.get('nodes');
            
            for (Object variantObj : variantNodes) {
                Map<String, Object> variantNode =
                    (Map<String, Object>) variantObj;
                
                if (variantNode == null) {
                    continue;
                }
                
                Map<String, Object> restVariant =
                    new Map<String, Object>();
                
                restVariant.put(
                    'id',
                    getLegacyId(variantNode)
                );
                
                restVariant.put(
                    'title',
                    variantNode.get('title')
                );
                
                restVariant.put(
                    'sku',
                    variantNode.get('sku')
                );
                
                restVariant.put(
                    'price',
                    variantNode.get('price')
                );
                
                restVariant.put(
                    'inventory_policy',
                    variantNode.get('inventoryPolicy')
                );
                
                Map<String, Object> inventoryItem =
                    (Map<String, Object>) variantNode.get(
                        'inventoryItem'
                    );
                
                if (inventoryItem != null) {
                    restVariant.put(
                        'inventory_item_id',
                        getLegacyId(inventoryItem)
                    );
                    
                    Map<String, Object> measurement =
                        (Map<String, Object>) inventoryItem.get(
                            'measurement'
                        );
                    
                    if (measurement != null) {
                        Map<String, Object> weight =
                            (Map<String, Object>) measurement.get(
                                'weight'
                            );
                        
                        if (weight != null) {
                            restVariant.put(
                                'weight',
                                weight.get('value')
                            );
                            
                            restVariant.put(
                                'weight_unit',
                                weight.get('unit')
                            );
                        }
                    }
                }
                
                Map<String, Object> variantImage =
                    (Map<String, Object>) variantNode.get('image');
                
                if (variantImage != null) {
                    restVariant.put(
                        'image_id',
                        extractNumericIdFromAnyShopifyId(
                            String.valueOf(
                                variantImage.get('id')
                            )
                        )
                    );
                }
                
                restVariant.put(
                    'selected_options',
                    variantNode.get('selectedOptions')
                );
                
                restVariants.add(restVariant);
            }
        }
        
        payload.put('variants', restVariants);
        
        return payload;
    }
    
    private static void addSimpleMetafield(
        List<Object> restMetafields,
        Map<String, Object> productNode,
        String aliasName
    ) {
        if (restMetafields == null || productNode == null) return;
        
        Map<String, Object> mf = (Map<String, Object>) productNode.get(aliasName);
        if (mf == null) return;
        
        Map<String, Object> restMf = new Map<String, Object>{
            'namespace' => mf.get('namespace'),
                'key' => mf.get('key'),
                'value' => mf.get('value')
                };
                    
                    if (mf.get('references') != null) {
                        restMf.put('references', mf.get('references'));
                    }
        
        restMetafields.add(restMf);
    }
    
    private static String joinGraphQLTags(Object rawTags) {
        if (rawTags == null) return null;
        
        if (rawTags instanceof List<Object>) {
            List<String> tagStrings = new List<String>();
            
            for (Object tagObj : (List<Object>) rawTags) {
                if (tagObj != null && !String.isBlank(String.valueOf(tagObj))) {
                    tagStrings.add(String.valueOf(tagObj));
                }
            }
            
            return String.join(tagStrings, ', ');
        }
        
        return String.valueOf(rawTags);
    }
    
    private static String getLegacyId(Map<String, Object> node) {
        if (node == null) return null;
        
        if (node.get('legacyResourceId') != null) {
            return String.valueOf(node.get('legacyResourceId'));
        }
        
        if (node.get('id') != null) {
            return extractNumericIdFromAnyShopifyId(String.valueOf(node.get('id')));
        }
        
        return null;
    }
    
    private static String extractNumericIdFromAnyShopifyId(String rawId) {
        if (String.isBlank(rawId)) {
            return null;
        }
        
        if (!rawId.contains('/')) {
            return rawId;
        }
        
        List<String> parts = rawId.split('/');
        return parts.isEmpty() ? null : parts[parts.size() - 1];
    }   
    
    // ── EXISTING: unchanged ───────────────────────────────────────────────────
    private static void validateUserErrors(Map<String, Object> response, String mutationName) {
        if (response == null || !response.containsKey('data')) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException(
                'Missing data from Shopify response.'
            );
        }
        
        Map<String, Object> data         = (Map<String, Object>) response.get('data');
        Map<String, Object> mutationResult = (Map<String, Object>) data.get(mutationName);
        List<Object>        userErrors   = (List<Object>) mutationResult.get('userErrors');
        
        if (userErrors != null && !userErrors.isEmpty()) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException(
                mutationName + ' userErrors: ' + JSON.serialize(userErrors)
            );
        }
    }
    
    private static String getGraphQLMetafieldValue(
        Map<String, Object> productNode,
        String aliasName
    ) {
        if (
            productNode == null ||
            String.isBlank(aliasName)
        ) {
            return null;
        }
        
        Object metafieldObject = productNode.get(aliasName);
        
        if (!(metafieldObject instanceof Map<String, Object>)) {
            return null;
        }
        
        Map<String, Object> metafield =
            (Map<String, Object>) metafieldObject;
        
        Object rawValue = metafield.get('value');
        
        if (rawValue == null) {
            return null;
        }
        
        String value = String.valueOf(rawValue);
        
        return String.isBlank(value)
            ? null
            : value.trim();
    }
}