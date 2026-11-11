public class OrderOrchestrationService {
    
    private static Map<String, Id> preResolvedLocationByOrderShopId = new Map<String, Id>();
    
    public static void processOrdersFromRestRequest(Map<String, Object> payload, String[] topicNames) {
        
        Map<String, List<SObject>> objectRecordsMap = new Map<String, List<SObject>>{
            'Order' => new List<SObject>(),
                'OrderItem' => new List<SObject>(),
                'Fulfilment__c' => new List<SObject>()
                };
                    
                    // Fetch the Standard Price Book Id once and pass it to the processing method
                    Id standardPriceBookId = [
                        SELECT Id
                        FROM Pricebook2
                        WHERE IsStandard = true
                        LIMIT 1
                    ].Id;
        
        // Fetch field mappings outside the loop to avoid repeated SOQL queries
        List<REST_Field_Mapping__mdt> fieldMappings = [
            SELECT SF_Field_Name__c,
            Request_Attribute__c,
            SF_Object_Name__c
            FROM REST_Field_Mapping__mdt
            WHERE Topic__c IN :topicNames
        ];
        
        if (payload != null && payload.containsKey('orders')) {
            List<Object> orders = (List<Object>) payload.get('orders');
            
            for (Object order : orders) {
                Map<String, Object> orderMap = (Map<String, Object>) order;
                
                if (orderMap != null) {
                    Id orderLocationId = resolveOrderLocationFromShopify(orderMap);
                    
                    if (orderMap.get('id') != null) {
                        preResolvedLocationByOrderShopId.put(
                            String.valueOf(orderMap.get('id')),
                            orderLocationId
                        );
                    }
                    
                    processCustomerFromOrder(orderMap); // Ensure customer is processed first
                    
                    Map<String, List<SObject>> processedRecordsMap =
                        processSingleOrder(
                            orderMap,
                            fieldMappings,
                            standardPriceBookId,
                            orderLocationId
                        );
                    
                    for (String key : objectRecordsMap.keySet()) {
                        if (processedRecordsMap.containsKey(key)) {
                            objectRecordsMap.get(key).addAll(processedRecordsMap.get(key));
                        }
                    }
                }
            }
            
        } else if (payload != null && payload.containsKey('order')) {
            Map<String, Object> orderMap = (Map<String, Object>) payload.get('order');
            
            if (orderMap != null) {
                Id shopLocationId = resolveOrderLocationFromShopify(orderMap);
                
                if (orderMap.get('id') != null) {
                    preResolvedLocationByOrderShopId.put(
                        String.valueOf(orderMap.get('id')),
                        shopLocationId
                    );
                }
                
                processCustomerFromOrder(orderMap); // Ensure customer is processed first
                
                objectRecordsMap =
                    processSingleOrder(
                        orderMap,
                        fieldMappings,
                        standardPriceBookId,
                        shopLocationId
                    );
            }
        }
        
        // Initialize the upsertResults list
        List<Database.UpsertResult> upsertResults = new List<Database.UpsertResult>();
        
        if (!objectRecordsMap.get('Order').isEmpty()) {
            System.debug('Just before insert');
            
            for (SObject thisObj : objectRecordsMap.get('Order')) {
                Order thisOrder = (Order) thisObj;
                System.debug(
                    'Shop Id: ' + thisOrder.Shop_ID__c +
                    ' Currency: ' + thisOrder.CurrencyISOCode
                );
            }
            
            upsertResults.addAll(
                Database.upsert(
                    objectRecordsMap.get('Order'),
                    Order.Shop_Id__c,
                    false
                )
            );
        }
        
        // New Order Insight sync
        if (!objectRecordsMap.get('OrderItem').isEmpty()) {
            
            List<OrderItem> validOrderItems =
                new List<OrderItem>();
            
            for (
                SObject sourceRecord :
                objectRecordsMap.get('OrderItem')
            ) {
                OrderItem sourceOrderItem =
                    (OrderItem) sourceRecord;
                
                if (
                    sourceOrderItem == null ||
                    String.isBlank(
                        sourceOrderItem.Shop_ID__c
                    )
                ) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'OrderItem excluded before upsert because Shop_ID__c is blank. ' +
                        'Record=' +
                        JSON.serialize(sourceOrderItem)
                    );
                    
                    continue;
                }
                
                if (
                    sourceOrderItem.PricebookEntryId == null
                ) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'OrderItem excluded before upsert because PricebookEntryId is blank. ' +
                        'Shop_ID__c=' +
                        sourceOrderItem.Shop_ID__c
                    );
                    
                    continue;
                }
                
                validOrderItems.add(sourceOrderItem);
            }
            
            if (!validOrderItems.isEmpty()) {
                Database.UpsertResult[] orderItemResults =
                    Database.upsert(
                        validOrderItems,
                        OrderItem.Shop_ID__c,
                        false
                    );
                
                upsertResults.addAll(orderItemResults);
                
                List<Id> successfulOrderItemIds =
                    new List<Id>();
                
                for (
                    Integer index = 0;
                    index < orderItemResults.size();
                    index++
                ) {
                    Database.UpsertResult result =
                        orderItemResults[index];
                    
                    OrderItem attemptedOrderItem =
                        validOrderItems[index];
                    
                    if (result.isSuccess()) {
                        successfulOrderItemIds.add(
                            result.getId()
                        );
                        
                        System.debug(
                            LoggingLevel.INFO,
                            'OrderItem upsert successful. ' +
                            'OrderItemId=' + result.getId() +
                            ', Shop_ID__c=' +
                            attemptedOrderItem.Shop_ID__c
                        );
                    } else {
                        for (
                            Database.Error errorRecord :
                            result.getErrors()
                        ) {
                            System.debug(
                                LoggingLevel.ERROR,
                                'OrderItem upsert failed. ' +
                                'Shop_ID__c=' +
                                attemptedOrderItem.Shop_ID__c +
                                ', OrderId=' +
                                attemptedOrderItem.OrderId +
                                ', PricebookEntryId=' +
                                attemptedOrderItem.PricebookEntryId +
                                ', Status=' +
                                errorRecord.getStatusCode() +
                                ', Message=' +
                                errorRecord.getMessage()
                            );
                        }
                    }
                }
                
                if (!successfulOrderItemIds.isEmpty()) {
                    Set<Id> productIdsForSalesInsight =
                        new Set<Id>();
                    
                    for (OrderItem savedOrderItem : [
                        SELECT Id, Product2Id
                        FROM OrderItem
                        WHERE Id IN :successfulOrderItemIds
                    ]) {
                        if (
                            savedOrderItem.Product2Id != null
                        ) {
                            productIdsForSalesInsight.add(
                                savedOrderItem.Product2Id
                            );
                        }
                    }
                    
                    if (
                        !productIdsForSalesInsight.isEmpty()
                    ) {
                        publishSalesInsightRefreshEvents(
                            productIdsForSalesInsight
                        );
                    }
                }
            }
        }
        
        // Old
        /*
if (!objectRecordsMap.get('OrderItem').isEmpty()) {
upsertResults.addAll(
Database.upsert(
objectRecordsMap.get('OrderItem'),
OrderItem.Shop_Id__c,
false
)
);
}
*/
        
        if (!objectRecordsMap.get('Fulfilment__c').isEmpty()) {
            List<Fulfilment__c> fulfilmentsToUpdate = new List<Fulfilment__c>();
            List<Fulfilment__c> fulfilmentsToUpsert = new List<Fulfilment__c>();
            
            for (SObject sobj : objectRecordsMap.get('Fulfilment__c')) {
                Fulfilment__c fulfilmentRecord = (Fulfilment__c) sobj;
                
                if (fulfilmentRecord.Id != null) {
                    fulfilmentsToUpdate.add(fulfilmentRecord);
                } else {
                    fulfilmentsToUpsert.add(fulfilmentRecord);
                }
            }
            
            if (!fulfilmentsToUpdate.isEmpty()) {
                Database.update(fulfilmentsToUpdate, false);
            }
            
            if (!fulfilmentsToUpsert.isEmpty()) {
                upsertResults.addAll(
                    Database.upsert(
                        fulfilmentsToUpsert,
                        Fulfilment__c.Shop_Id__c,
                        false
                    )
                );
            }
        }
        
        /*
 * FINALIZE SALESFORCE ORDER STATUS:
 * Shopify order records are initially created as Draft because Salesforce
 * OrderItems are inserted after the Order record.
 *
 * After OrderItems and Fulfilment records are processed, finalize the
 * Salesforce Order status based on the financial status.
 *
 * Paid orders should become Success.
 * All other successfully synced orders should become Open.
 */
        finalizeSalesforceOrderStatus(objectRecordsMap);
        
        System.debug('upsertResults are ' + upsertResults);
    }
    
    private static void finalizeSalesforceOrderStatus(
        Map<String, List<SObject>> objectRecordsMap
    ) {
        if (
            objectRecordsMap == null ||
            !objectRecordsMap.containsKey('Order') ||
            objectRecordsMap.get('Order') == null ||
            objectRecordsMap.get('Order').isEmpty()
        ) {
            return;
        }
        
        List<Order> ordersToFinalize = new List<Order>();
        
        for (SObject orderSObj : objectRecordsMap.get('Order')) {
            Order syncedOrder = (Order) orderSObj;
            
            if (
                syncedOrder == null ||
                String.isBlank(syncedOrder.Shop_ID__c)
            ) {
                continue;
            }
            
            String finalStatus =
                deriveSalesforceOrderStatusAfterSync(syncedOrder);
            
            ordersToFinalize.add(new Order(
                Shop_ID__c = syncedOrder.Shop_ID__c,
                Status = finalStatus
            ));
        }
        
        if (ordersToFinalize.isEmpty()) {
            return;
        }
        
        Database.UpsertResult[] finalizeResults =
            Database.upsert(
                ordersToFinalize,
                Order.Shop_ID__c,
                false
            );
        
        for (Integer i = 0; i < finalizeResults.size(); i++) {
            if (finalizeResults[i].isSuccess()) {
                System.debug(
                    LoggingLevel.INFO,
                    'OrderOrchestrationService: Finalized Salesforce Order status. ' +
                    'Shop_ID__c=' + ordersToFinalize[i].Shop_ID__c +
                    ', Status=' + ordersToFinalize[i].Status
                );
            } else {
                for (Database.Error err : finalizeResults[i].getErrors()) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'OrderOrchestrationService: Failed to finalize Salesforce Order status. ' +
                        'Shop_ID__c=' + ordersToFinalize[i].Shop_ID__c +
                        ', Status=' + err.getStatusCode() +
                        ', Message=' + err.getMessage()
                    );
                }
            }
        }
    }    
    
    private static String deriveSalesforceOrderStatusAfterSync(Order orderRecord) {
        if (orderRecord == null) {
            return 'Open';
        }
        
        String financialStatus = orderRecord.Financial_Status__c;
        
        if (
            !String.isBlank(financialStatus) &&
            financialStatus.trim().equalsIgnoreCase('Paid')
        ) {
            return 'Success';
        }
        
        return 'Open';
    }
    
    // Ensure customer is processed before order
    private static void processCustomerFromOrder(Map<String, Object> orderMap) {
        if (orderMap != null && orderMap.containsKey('customer')) {
            Map<String, Object> customerMap =
                new Map<String, Object>{ 'customer' => orderMap.get('customer') };
                    
                    if (customerMap.get('customer') != null) {
                        AccountOrchestrationService.processCustomersFromRestRequest(
                            customerMap,
                            new String[] { 'customers' }
                        );
                    } else {
                        AccountOrchestrationService.processDefaultCustomer();
                    }
        }
    }
    
    public static Map<String, List<SObject>> processSingleOrder(
        Map<String, Object> payload,
        List<REST_Field_Mapping__mdt> fieldMappings,
        Id standardPriceBookId,
        Id shopLocationId
    ) {
        if (payload != null && payload.get('id') != null) {
            preResolvedLocationByOrderShopId.put(
                String.valueOf(payload.get('id')),
                shopLocationId
            );
        }
        
        return processSingleOrder(
            payload,
            fieldMappings,
            standardPriceBookId
        );
    }
    
    public static Map<String, List<SObject>> processSingleOrder(
        Map<String, Object> payload,
        List<REST_Field_Mapping__mdt> fieldMappings,
        Id standardPriceBookId
    ) {
        
        Map<String, List<SObject>> objectRecordsMap = new Map<String, List<SObject>>{
            'Order' => new List<SObject>(),
                'OrderItem' => new List<SObject>(),
                'Fulfilment__c' => new List<SObject>()
                };
                    
                    if (payload == null) {
                        return objectRecordsMap;
                    }
        
        // Group field mappings by Salesforce object
        Map<String, List<REST_Field_Mapping__mdt>> fieldMappingsGroupedBySFObject =
            new Map<String, List<REST_Field_Mapping__mdt>>();
        
        for (REST_Field_Mapping__mdt thisMapping : fieldMappings) {
            String sfObjectName = thisMapping.SF_Object_Name__c;
            
            if (!fieldMappingsGroupedBySFObject.containsKey(sfObjectName)) {
                fieldMappingsGroupedBySFObject.put(
                    sfObjectName,
                    new List<REST_Field_Mapping__mdt>()
                );
            }
            
            fieldMappingsGroupedBySFObject.get(sfObjectName).add(thisMapping);
        }
        
        // Process Order and add to ordersToInsert list
        Order newOrderRecord;
        
        if (fieldMappingsGroupedBySFObject.containsKey('Order')) {
            
            SObject newOrderRecordSobject =
                Utilities.doGenericMapping(
                    'Order',
                    payload,
                    fieldMappingsGroupedBySFObject.get('Order')
                );
            
            newOrderRecord = (Order) newOrderRecordSobject;
            
            // Set Shopify Record Type
            newOrderRecord.RecordTypeId =
                Schema.SObjectType.Order.getRecordTypeInfosByDeveloperName()
                .get('Shopify')
                .getRecordTypeId();
            
            // Convert currencies other than accepted ones to GBP
            if ((String) payload.get('currency') != null &&
                (String) payload.get('currency') != 'GBP') {
                    newOrderRecord.CurrencyIsoCode = 'GBP';
                }
            
            // Attach the right customer record Every Order will have 1 Customer
            Map<String, Object> customerMap =
                (Map<String, Object>) payload.get('customer');
            
            Account accountReference;
            
            if (customerMap != null) {
                accountReference =
                    new Account(Shop_Id__c = String.valueOf(customerMap.get('id')));
            } else {
                accountReference = new Account(Shop_Id__c = '1010101');
            }
            
            Id shopLocationId = getPreResolvedOrderLocation(payload);
            
            if (shopLocationId != null) {
                newOrderRecord.Location__c = shopLocationId;
            }
            
            newOrderRecord.Account = accountReference;
            
            // Attach Standard Price Book to Order
            newOrderRecord.Pricebook2Id = standardPriceBookId;
            newOrderRecord.Type = 'Shopify Order';
            
            // newOrderRecord.Location__c = shopLocationId;
            doNuancedMapping(newOrderRecord, payload);
            
            // doNuancedMapping(newOrderRecord, payload);
            
            // Fulfillment status mapping
            
            newOrderRecord.Fulfillment_Status__c = deriveOrderFulfillmentStatus(payload);
            applyInboundRefundFields(newOrderRecord, payload);
            objectRecordsMap.get('Order').add(newOrderRecord);
        }
        
        // Process OrderItem - defer insertion until Order is inserted
        if (payload.containsKey('line_items') &&
            fieldMappingsGroupedBySFObject.containsKey('OrderItem')) {
                
                List<Object> lineItems = (List<Object>) payload.get('line_items');
                
                Map<String, Id> variantShopIdPBEMap = new Map<String, Id>();
                
                for (PricebookEntry thisPBE : [
                    SELECT Id, Pricebook2Id, Product2.Shop_Id__c
                    FROM PricebookEntry
                    WHERE Pricebook2Id IN (
                        SELECT Id
                        FROM Pricebook2
                        WHERE IsStandard = true 

                    )
                ]) {
                    variantShopIdPBEMap.put(thisPBE.Product2.Shop_Id__c, thisPBE.Id);
                }
                
                //Product Name matching logic - WB Integration
                Map<String, List<PricebookEntry>> normalizedNameToPBEMap =
                    new Map<String, List<PricebookEntry>>();
                
                for (PricebookEntry thisPBE : [
                    SELECT Id, Product2Id, Product2.Name, Product2.Type__c, Product2.IsActive
                    FROM PricebookEntry
                    WHERE Pricebook2Id = :standardPriceBookId 
                    AND IsActive = true
                    AND Product2.Name != null
                ]) {
                    String normalizedProductName =
                        normalizeProductName(thisPBE.Product2.Name);
                    
                    if (String.isBlank(normalizedProductName)) {
                        continue;
                    }
                    
                    if (!normalizedNameToPBEMap.containsKey(normalizedProductName)) {
                        normalizedNameToPBEMap.put(
                            normalizedProductName,
                            new List<PricebookEntry>()
                        );
                    }
                    
                    normalizedNameToPBEMap.get(normalizedProductName).add(thisPBE);
                }
                
                for (Object lineItem : lineItems) {
                    Map<String, Object> lineItemMap = (Map<String, Object>) lineItem;
                    
                    if (lineItemMap != null) {
                        SObject newOrderItemRecord =
                            Utilities.doGenericMapping(
                                'OrderItem',
                                lineItemMap,
                                fieldMappingsGroupedBySFObject.get('OrderItem')
                            );
                        
                        OrderItem thisOrderItem =
                            (OrderItem) newOrderItemRecord;
                        
                        /*
* Do not depend only on REST_Field_Mapping__mdt.
* Explicitly copy the Shopify line-item ID.
*/
                        if (
                            lineItemMap.containsKey('id') &&
                            lineItemMap.get('id') != null
                        ) {
                            thisOrderItem.Shop_ID__c =
                                String.valueOf(lineItemMap.get('id'));
                        }
                        
                        if (String.isBlank(thisOrderItem.Shop_ID__c)) {
                            System.debug(
                                LoggingLevel.ERROR,
                                'Skipping Shopify OrderItem because line-item id is missing. ' +
                                'OrderShopId=' + String.valueOf(payload.get('id')) +
                                ', LineItem=' + JSON.serialize(lineItemMap)
                            );
                            
                            continue;
                        }
                        
                        Order orderReference = new Order(
                            Shop_ID__c = String.valueOf(payload.get('id'))
                        );
                        
                        String variantShopId =
                            lineItemMap.get('variant_id') == null
                            ? null
                            : String.valueOf(lineItemMap.get('variant_id'));
                        
                        Id pricebookEntryId =
                            String.isBlank(variantShopId)
                            ? null
                            : variantShopIdPBEMap.get(variantShopId);
                        
                        //Part of Name matching logic
                        String salesChannelForNameFallback = deriveSalesChannel(payload);
                        
                        if (
                            pricebookEntryId == null &&
                            salesChannelForNameFallback == 'WB Integration'
                        ) {
                            pricebookEntryId =
                                resolvePricebookEntryByLineItemName(
                                    lineItemMap,
                                    normalizedNameToPBEMap,
                                    String.valueOf(payload.get('id')),
                                    thisOrderItem.Shop_ID__c
                                );
                        }
                        
                        if (pricebookEntryId == null) {
                            System.debug(
                                LoggingLevel.ERROR,
                                'Skipping Shopify OrderItem because no Standard PricebookEntry was found. ' +
                                'OrderShopId=' + String.valueOf(payload.get('id')) +
                                ', LineItemShopId=' + thisOrderItem.Shop_ID__c +
                                ', VariantShopId=' + variantShopId
                            );
                            
                            continue;
                        }
                        
                        thisOrderItem.Order = orderReference;
                        thisOrderItem.PricebookEntryId = pricebookEntryId;
                        
                        objectRecordsMap.get('OrderItem').add(
                            thisOrderItem
                        );
                    }
                }
            }
        
        // Process Fulfilment - keep only one Fulfilment__c per Shopify Order
        if (payload.containsKey('fulfillments') &&
            fieldMappingsGroupedBySFObject.containsKey('Fulfilment__c')) {
                
                List<Object> fulfillments = (List<Object>) payload.get('fulfillments');
                
                if (fulfillments != null && !fulfillments.isEmpty()) {
                    String orderShopId = String.valueOf(payload.get('id'));
                    
                    List<Fulfilment__c> existingFulfilments = [
                        SELECT Id, Shop_ID__c, Order__c
                        FROM Fulfilment__c
                        WHERE Order__r.Shop_ID__c = :orderShopId
                        LIMIT 1
                    ];
                    
                    Id existingFulfilmentId =
                        existingFulfilments.isEmpty() ? null : existingFulfilments[0].Id;
                    
                    Map<String, Object> fulfillmentMap =
                        (Map<String, Object>) fulfillments[0];
                    
                    if (fulfillmentMap != null) {
                        SObject newFulfillmentRecord =
                            Utilities.doGenericMapping(
                                'Fulfilment__c',
                                fulfillmentMap,
                                fieldMappingsGroupedBySFObject.get('Fulfilment__c')
                            );
                        
                        Fulfilment__c thisFulfilment =
                            (Fulfilment__c) newFulfillmentRecord;
                        
                        if (existingFulfilmentId != null) {
                            thisFulfilment.Id = existingFulfilmentId;
                        }
                        
                        Order orderReference = new Order(Shop_Id__c = orderShopId);
                        
                        thisFulfilment.Order__r = orderReference;
                        thisFulfilment.Status__c = deriveFulfillmentDisplayStatus(payload, fulfillmentMap);
                        
                        objectRecordsMap.get('Fulfilment__c').add(thisFulfilment);
                    }
                }
            }
        
        return objectRecordsMap;
    }
    
    private static Id resolvePricebookEntryByLineItemName(
        Map<String, Object> lineItemMap,
        Map<String, List<PricebookEntry>> normalizedNameToPBEMap,
        String orderShopId,
        String lineItemShopId
    ) {
        if (lineItemMap == null || normalizedNameToPBEMap == null) {
            return null;
        }
        
        String lineItemName = getLineItemProductName(lineItemMap);
        String normalizedLineItemName = normalizeProductName(lineItemName);
        
        if (String.isBlank(normalizedLineItemName)) {
            System.debug(
                LoggingLevel.WARN,
                'OrderOrchestrationService: Cannot match Shopify OrderItem by name because line item name is blank. ' +
                'OrderShopId=' + orderShopId +
                ', LineItemShopId=' + lineItemShopId
            );
            
            return null;
        }
        
        List<PricebookEntry> matchingPBEs =
            normalizedNameToPBEMap.get(normalizedLineItemName);
        
        if (matchingPBEs == null || matchingPBEs.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'OrderOrchestrationService: No Product2 name match found for Shopify OrderItem. ' +
                'OrderShopId=' + orderShopId +
                ', LineItemShopId=' + lineItemShopId +
                ', LineItemName=' + lineItemName +
                ', NormalizedName=' + normalizedLineItemName
            );
            
            return null;
        }
        
        if (matchingPBEs.size() > 1) {
            System.debug(
                LoggingLevel.ERROR,
                'OrderOrchestrationService: Multiple Product2 name matches found for Shopify OrderItem. ' +
                'Skipping to avoid wrong product mapping. ' +
                'OrderShopId=' + orderShopId +
                ', LineItemShopId=' + lineItemShopId +
                ', LineItemName=' + lineItemName +
                ', NormalizedName=' + normalizedLineItemName +
                ', MatchCount=' + matchingPBEs.size()
            );
            
            return null;
        }
        
        System.debug(
            LoggingLevel.INFO,
            'OrderOrchestrationService: Matched Shopify OrderItem by Product2 name fallback. ' +
            'OrderShopId=' + orderShopId +
            ', LineItemShopId=' + lineItemShopId +
            ', LineItemName=' + lineItemName +
            ', PricebookEntryId=' + matchingPBEs[0].Id +
            ', Product2Id=' + matchingPBEs[0].Product2Id
        );
        
        return matchingPBEs[0].Id;
    }
    
    //Helper methods for name matching rules
    private static String getLineItemProductName(Map<String, Object> lineItemMap) {
        if (lineItemMap == null) {
            return null;
        }
        
        if (lineItemMap.containsKey('title') && lineItemMap.get('title') != null) {
            return String.valueOf(lineItemMap.get('title'));
        }
        
        if (lineItemMap.containsKey('name') && lineItemMap.get('name') != null) {
            return String.valueOf(lineItemMap.get('name'));
        }
        
        if (lineItemMap.containsKey('product_title') && lineItemMap.get('product_title') != null) {
            return String.valueOf(lineItemMap.get('product_title'));
        }
        
        return null;
    }
    
    @TestVisible
    private static String normalizeProductName(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        
        String normalized = value.trim().toLowerCase();
        
        normalized = normalized.replace('-', ' ');
        normalized = normalized.replace('_', ' ');
        normalized = normalized.replaceAll('[^a-z0-9 ]', ' ');
        normalized = normalized.replaceAll('\\s+', ' ');
        normalized = normalized.trim();
        
        List<String> cleanTokens = new List<String>();
        
        for (String token : normalized.split(' ')) {
            if (String.isBlank(token)) {
                continue;
            }
            
            String cleanToken = normalizeProductNameToken(token);
            
            if (String.isBlank(cleanToken)) {
                continue;
            }
            
            cleanTokens.add(cleanToken);
        }
        
        if (cleanTokens.isEmpty()) {
            return null;
        }
        
        return String.join(cleanTokens, ' ');
    }
    
    private static String normalizeProductNameToken(String token) {
        if (String.isBlank(token)) {
            return null;
        }
        
        String cleanToken = token.trim().toLowerCase();
        
        /*
* Remove generic category words.
* These words may be added by WB / Shopify line item names,
* but may not exist in Salesforce Product2.Name.
*/
        Set<String> ignoredWords = new Set<String>{
            'earring',
                'earrings',
                'necklace',
                'necklaces',
                'bracelet',
                'bracelets',
                'ring',
                'rings',
                'anklet',
                'anklets',
                'jewelry',
                'jewellery'
                };
                    
                    if (ignoredWords.contains(cleanToken)) {
                        return null;
                    }
        
        /*
* Normalize common plural endings.
* Example: huggies -> huggie
*/
        if (cleanToken.endsWith('ies') && cleanToken.length() > 4) {
            cleanToken = cleanToken.substring(0, cleanToken.length() - 3) + 'y';
        } else if (cleanToken.endsWith('s') && cleanToken.length() > 4) {
            cleanToken = cleanToken.substring(0, cleanToken.length() - 1);
        }
        
        return cleanToken;
    }
    
    private static Id getPreResolvedOrderLocation(Map<String, Object> orderPayload) {
        if (orderPayload == null || orderPayload.get('id') == null) {
            return null;
        }
        
        String orderShopId = String.valueOf(orderPayload.get('id'));
        
        if (preResolvedLocationByOrderShopId.containsKey(orderShopId)) {
            return preResolvedLocationByOrderShopId.get(orderShopId);
        }
        
        Id resolvedLocationId = resolveOrderLocationFromShopify(orderPayload);
        
        preResolvedLocationByOrderShopId.put(orderShopId, resolvedLocationId);
        
        return resolvedLocationId;
    }
    
    @TestVisible
    private static Id resolveOrderLocationFromShopify(Map<String, Object> orderPayload) {
        
        /*
* IMPORTANT:
* Do not make Shopify GraphQL / HTTP callouts from this method.
*
* This method is called from Shopify_Order__e platform event processing.
* The current failure is:
* "Callout from triggers are currently not supported."
*
* New pattern:
* Order Type -> Inventory_Rules__mdt -> Location -> Salesforce Location Id
*/
        
        String orderType = 'Shopify Order';
        
        if (orderPayload != null) {
            Object rawType = orderPayload.get('type');
            
            if (rawType != null && !String.isBlank(String.valueOf(rawType))) {
                orderType = String.valueOf(rawType);
            }
        }
        
        Id locationId = InventoryRuleService.getLocationIdForOrderType(orderType);
        
        if (locationId != null) {
            System.debug(
                LoggingLevel.INFO,
                'OrderOrchestrationService.resolveOrderLocationFromShopify: resolved location using Inventory Rules. ' +
                'orderType=' + orderType +
                ', locationId=' + locationId
            );
            
            return locationId;
        }
        
        /*
* Fallback:
* If metadata does not match "Shopify Order", try "Shopify".
* This is useful because Danny mentioned Shopify in the meeting,
* but your Salesforce Order.Type value is "Shopify Order".
*/
        if (orderType != 'Shopify') {
            locationId = InventoryRuleService.getLocationIdForOrderType('Shopify');
            
            if (locationId != null) {
                System.debug(
                    LoggingLevel.WARN,
                    'OrderOrchestrationService.resolveOrderLocationFromShopify: resolved location using fallback Inventory Rule. ' +
                    'originalOrderType=' + orderType +
                    ', fallbackOrderType=Shopify' +
                    ', locationId=' + locationId
                );
                
                return locationId;
            }
        }
        
        /*
* Final fallback:
* Keep this fallback so the Order can still be created even if metadata is missing.
* This does not call Shopify.
*/
        List<SObject> warehouseLocations = Database.query(
            'SELECT Id, Name FROM Location WHERE Name = \'Warehouse\' LIMIT 1'
        );
        
        if (!warehouseLocations.isEmpty()) {
            Id warehouseLocationId = (Id) warehouseLocations[0].get('Id');
            
            System.debug(
                LoggingLevel.WARN,
                'OrderOrchestrationService.resolveOrderLocationFromShopify: Inventory Rule missing. ' +
                'Falling back to Location.Name = Warehouse. locationId=' + warehouseLocationId
            );
            
            return warehouseLocationId;
        }
        
        System.debug(
            LoggingLevel.WARN,
            'OrderOrchestrationService.resolveOrderLocationFromShopify: no Inventory Rule and no Warehouse Location found.'
        );
        
        return null;
    }
    
    @TestVisible
    private static String extractNumericIdFromGid(String gid) {
        if (String.isBlank(gid)) {
            return null;
        }
        
        List<String> parts = gid.split('/');
        
        return parts.isEmpty() ? null : parts[parts.size() - 1];
    }
    
    private static void publishSalesInsightRefreshEvents(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return;
        }
        
        List<Shopify_Product__e> eventsToPublish = new List<Shopify_Product__e>();
        
        for (Product2 p : [
            SELECT Id, Shop_ID__c
            FROM Product2
            WHERE Id IN :productIds
            AND Shop_ID__c != null
        ]) {
            Shopify_Product__e evt = new Shopify_Product__e();
            
            // Use this as the routing key in the platform event handler
            evt.ShopifyTopic__c = 'sales_insight_refresh';
            
            // Keep using existing event field.
            // Here this value is the Shopify Product/Variant Shop Id from Product2.
            evt.Shop_ID__c = p.Shop_ID__c;
            
            evt.ShopifyTriggeredAt__c = System.now();
            evt.ShopifyTest__c = false;
            
            eventsToPublish.add(evt);
        }
        
        if (!eventsToPublish.isEmpty()) {
            Database.SaveResult[] results = EventBus.publish(eventsToPublish);
            
            for (Database.SaveResult sr : results) {
                if (!sr.isSuccess()) {
                    for (Database.Error err : sr.getErrors()) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'Failed to publish sales insight platform event: ' +
                            err.getStatusCode() + ' - ' + err.getMessage()
                        );
                    }
                }
            }
        }
    }
    
    private static String deriveOrderFulfillmentStatus(Map<String, Object> orderPayload) {
        if (orderPayload == null) {
            return 'Pending';
        }
        
        String fulfillmentStatus = getLowerString(orderPayload, 'fulfillment_status');
        
        if (
            String.isBlank(fulfillmentStatus) ||
            fulfillmentStatus == 'null' ||
            fulfillmentStatus == 'unfulfilled'
        ) {
            return 'Unfulfilled';
        }
        
        if (fulfillmentStatus == 'pending') {
            return 'Pending';
        }
        
        if (fulfillmentStatus == 'open') {
            return 'Open';
        }
        
        if (
            fulfillmentStatus == 'partial' ||
            fulfillmentStatus == 'partially_fulfilled'
        ) {
            return 'PartiallyFulfilled';
        }
        
        if (
            fulfillmentStatus == 'fulfilled' ||
            fulfillmentStatus == 'success'
        ) {
            return 'Fulfilled';
        }
        
        if (fulfillmentStatus == 'restocked') {
            return 'Restocked';
        }
        
        if (fulfillmentStatus == 'scheduled') {
            return 'Scheduled';
        }
        
        if (
            fulfillmentStatus == 'on_hold' ||
            fulfillmentStatus == 'on hold' ||
            fulfillmentStatus == 'onhold'
        ) {
            return 'OnHold';
        }
        
        if (
            fulfillmentStatus == 'in_progress' ||
            fulfillmentStatus == 'in progress' ||
            fulfillmentStatus == 'processing'
        ) {
            return 'In-Progress';
        }
        
        return 'PendingFulfillment';
    }
    
    @TestVisible
    private static String deriveOrderFulfillmentDisplayStatus(Map<String, Object> orderPayload) {
        if (orderPayload == null) {
            return 'Pending';
        }
        
        List<Object> fulfillments = null;
        
        if (orderPayload.containsKey('fulfillments') && orderPayload.get('fulfillments') != null) {
            fulfillments = (List<Object>) orderPayload.get('fulfillments');
        }
        
        if (fulfillments != null && !fulfillments.isEmpty()) {
            Map<String, Object> latestFulfillment = null;
            
            for (Object fulfillmentObj : fulfillments) {
                Map<String, Object> fulfillmentMap = (Map<String, Object>) fulfillmentObj;
                
                if (fulfillmentMap == null) {
                    continue;
                }
                
                latestFulfillment = fulfillmentMap;
            }
            
            if (latestFulfillment != null) {
                return deriveFulfillmentDisplayStatus(orderPayload, latestFulfillment);
            }
        }
        
        String fulfillmentStatus = getLowerString(orderPayload, 'fulfillment_status');
        
        if (String.isBlank(fulfillmentStatus) || fulfillmentStatus == 'null' || fulfillmentStatus == 'unfulfilled') {
            return 'Pending';
        }
        
        if (fulfillmentStatus == 'partial') {
            return 'Processing';
        }
        
        if (fulfillmentStatus == 'fulfilled') {
            return 'Processing';
        }
        
        if (fulfillmentStatus == 'restocked') {
            return 'Cancelled';
        }
        
        return 'Pending';
    }
    
    private static String deriveFulfillmentDisplayStatus(
        Map<String, Object> orderPayload,
        Map<String, Object> fulfillmentMap
    ) {
        if (fulfillmentMap == null) {
            return deriveOrderFulfillmentDisplayStatus(orderPayload);
        }
        
        String fulfillmentStatus = getLowerString(fulfillmentMap, 'status');
        String shipmentStatus = getLowerString(fulfillmentMap, 'shipment_status');
        
        String combinedText = (
            String.valueOf(fulfillmentStatus) + ' ' +
            String.valueOf(shipmentStatus) + ' ' +
            flattenPayloadText(fulfillmentMap) + ' ' +
            flattenPayloadText(orderPayload)
        ).toLowerCase();
        
        // Delivered must win over "delivered by" only when it clearly says delivered/completed.
        if (
            shipmentStatus == 'delivered' ||
            fulfillmentStatus == 'delivered' ||
            containsAny(combinedText, new List<String>{
                'status delivered',
                    'successfully delivered',
                    'has been delivered',
                    'was delivered',
                    'delivered on',
                    'delivered at'
                    })
        ) {
            return 'Delivered';
        }
        
        if (
            shipmentStatus == 'out_for_delivery' ||
            shipmentStatus == 'out for delivery' ||
            containsAny(combinedText, new List<String>{
                'out for delivery'
                    })
        ) {
            return 'Out for Delivery';
        }
        
        if (
            shipmentStatus == 'attempted_delivery' ||
            shipmentStatus == 'attempted delivery' ||
            containsAny(combinedText, new List<String>{
                'attempted delivery',
                    'delivery attempted'
                    })
        ) {
            return 'Attempted Delivery';
        }
        
        if (
            shipmentStatus == 'failure' ||
            fulfillmentStatus == 'failure' ||
            containsAny(combinedText, new List<String>{
                'delivery failed',
                    'failed delivery',
                    'unable to deliver',
                    'returned to sender'
                    })
        ) {
            return 'Failure';
        }
        
        if (
            fulfillmentStatus == 'cancelled' ||
            fulfillmentStatus == 'canceled' ||
            shipmentStatus == 'cancelled' ||
            shipmentStatus == 'canceled'
        ) {
            return 'Cancelled';
        }
        
        if (
            fulfillmentStatus == 'error' ||
            shipmentStatus == 'error'
        ) {
            return 'Error';
        }
        
        if (
            shipmentStatus == 'ready_for_pickup' ||
            shipmentStatus == 'ready for pickup' ||
            shipmentStatus == 'picked_up' ||
            shipmentStatus == 'picked up' ||
            containsAny(combinedText, new List<String>{
                'ready for pickup',
                    'ready to pick up',
                    'picked up'
                    })
        ) {
            return 'Ready for Pickup';
        }
        
        if (
            shipmentStatus == 'in_transit' ||
            shipmentStatus == 'in transit' ||
            shipmentStatus == 'confirmed' ||
            shipmentStatus == 'carrier_picked_up' ||
            shipmentStatus == 'carrier picked up' ||
            containsAny(combinedText, new List<String>{
                'in transit',
                    'on the way',
                    'on its way',
                    'with carrier',
                    'picked up by carrier',
                    'delivered by',
                    'delivery by',
                    'estimated delivery',
                    'arrives between',
                    'delivery between',
                    'between 17',
                    'between 18',
                    'between 19'
                    })
        ) {
            return 'In Transit';
        }
        
        if (
            shipmentStatus == 'label_printed' ||
            shipmentStatus == 'label purchased' ||
            shipmentStatus == 'label_purchased' ||
            fulfillmentStatus == 'open' ||
            fulfillmentStatus == 'pending'
        ) {
            return 'Processing';
        }
        
        if (fulfillmentStatus == 'success') {
            if (
                fulfillmentMap.containsKey('tracking_number') ||
                fulfillmentMap.containsKey('tracking_numbers') ||
                fulfillmentMap.containsKey('tracking_url') ||
                fulfillmentMap.containsKey('tracking_urls') ||
                fulfillmentMap.containsKey('tracking_company')
            ) {
                return 'In Transit';
            }
            
            return 'Processing';
        }
        
        return 'Pending';
    }
    
    private static String getLowerString(Map<String, Object> sourceMap, String key) {
        if (sourceMap == null || String.isBlank(key)) {
            return null;
        }
        
        if (!sourceMap.containsKey(key) || sourceMap.get(key) == null) {
            return null;
        }
        
        return String.valueOf(sourceMap.get(key)).trim().toLowerCase();
    }
    
    private static Boolean containsAny(String sourceText, List<String> keywords) {
        if (String.isBlank(sourceText) || keywords == null || keywords.isEmpty()) {
            return false;
        }
        
        String normalizedSource = sourceText.toLowerCase();
        
        for (String keyword : keywords) {
            if (!String.isBlank(keyword) && normalizedSource.contains(keyword.toLowerCase())) {
                return true;
            }
        }
        
        return false;
    }
    
    private static String flattenPayloadText(Object value) {
        if (value == null) {
            return '';
        }
        
        String result = '';
        
        if (value instanceof Map<String, Object>) {
            Map<String, Object> valueMap = (Map<String, Object>) value;
            
            for (String key : valueMap.keySet()) {
                result += ' ' + key + ' ' + flattenPayloadText(valueMap.get(key));
            }
            
            return result;
        }
        
        if (value instanceof List<Object>) {
            List<Object> valueList = (List<Object>) value;
            
            for (Object item : valueList) {
                result += ' ' + flattenPayloadText(item);
            }
            
            return result;
        }
        
        return String.valueOf(value);
    }
    
    @TestVisible
    private static String deriveSalesChannel(
        Map<String, Object> orderPayload
    ) {
        if (orderPayload == null) {
            return null;
        }
        
        String sourceName = orderPayload.get('source_name') == null
            ? null
            : String.valueOf(orderPayload.get('source_name')).trim();
        
        String appId = orderPayload.get('app_id') == null
            ? null
            : String.valueOf(orderPayload.get('app_id')).trim();
        
        /*
* Production WB Integration source.
* Include both source_name and app_id checks because Shopify
* integrations may expose the identifier through either field.
*/
        if (
            sourceName == '313746587649' ||
            appId == '313746587649'
        ) {
            return 'WB Integration';
        }
        
        if (!String.isBlank(sourceName)) {
            String normalizedSource =
                sourceName.toLowerCase();
            
            if (
                normalizedSource == 'web' ||
                normalizedSource == 'online_store' ||
                normalizedSource.contains('online store')
            ) {
                return 'Online Store';
            }
            
            if (
                normalizedSource.contains('draft') ||
                normalizedSource == 'shopify_draft_order'
            ) {
                return 'Draft';
            }
            
            if (
                normalizedSource.contains('wb') ||
                normalizedSource.contains('integration')
            ) {
                return 'WB Integration';
            }
        }
        
        /*
* Do not assign an incorrect default when the source is unknown.
*/
        return null;
    }
    
    private static void applyInboundRefundFields(
    Order orderRecord,
    Map<String, Object> payload
) {
    if (orderRecord == null || payload == null) {
        return;
    }

    String financialStatus = getLowerString(payload, 'financial_status');

    Boolean isRefundedStatus =
        financialStatus == 'refunded' ||
        financialStatus == 'partially_refunded' ||
        financialStatus == 'partially refunded';

    if (!isRefundedStatus && !payload.containsKey('refunds')) {
        return;
    }

    List<Object> refunds = null;

    if (payload.containsKey('refunds') && payload.get('refunds') != null) {
        refunds = (List<Object>) payload.get('refunds');
    }

    if (refunds == null || refunds.isEmpty()) {
        System.debug(
            LoggingLevel.WARN,
            'OrderOrchestrationService: Order is refunded but refunds array is empty. ' +
            'OrderShopId=' + String.valueOf(payload.get('id'))
        );
        return;
    }

    Map<String, Object> latestRefund = getLatestRefund(refunds);

    if (latestRefund == null) {
        return;
    }

    Datetime refundDate = parseShopifyDatetime(
        getFirstNonBlankValue(
            latestRefund,
            new List<String>{
                'created_at',
                'processed_at',
                'updated_at'
            }
        )
    );
    
    if (refundDate != null) {
        orderRecord.Refund_Date__c = refundDate;
    }
    
    String refundReason = getFirstNonBlankValue(
        latestRefund,
        new List<String>{
            'note',
                'reason',
                'message'
                }
    );
    
    if (!String.isBlank(refundReason)) {
        orderRecord.Refund_Reason__c = refundReason;
    }
    
    Decimal refundAmount = deriveRefundAmount(latestRefund);
    
    if (refundAmount != null && refundAmount > 0) {
        orderRecord.Refund_Amount__c = refundAmount;
    }
    
    System.debug(
        LoggingLevel.INFO,
        'OrderOrchestrationService: Applied inbound Shopify refund fields. ' +
        'OrderShopId=' + String.valueOf(payload.get('id')) +
        ', RefundDate=' + orderRecord.Refund_Date__c +
        ', RefundReason=' + orderRecord.Refund_Reason__c +
        ', RefundAmount=' + orderRecord.Refund_Amount__c
    );
}
    
    private static Map<String, Object> getLatestRefund(List<Object> refunds) {
        Map<String, Object> latestRefund = null;
        Datetime latestDate = null;
        
        for (Object refundObj : refunds) {
            Map<String, Object> refundMap = (Map<String, Object>) refundObj;
            
            if (refundMap == null) {
                continue;
            }
            
            Datetime refundDate = parseShopifyDatetime(
                getFirstNonBlankValue(
                    refundMap,
                    new List<String>{
                        'created_at',
                            'processed_at',
                            'updated_at'
                            }
                )
            );
            
            if (
                latestRefund == null ||
                refundDate == null ||
                latestDate == null ||
                refundDate.getTime() >= latestDate.getTime()
            ) {
                latestRefund = refundMap;
                
                if (refundDate != null) {
                    latestDate = refundDate;
                }
            }
        }
        
        return latestRefund;
    }
    
    private static Decimal deriveRefundAmount(Map<String, Object> refundMap) {
        if (refundMap == null) {
            return null;
        }
        
        Decimal amount = 0;
        
        /*
* Shopify REST refunds usually include transactions.
* Refund transaction amount is the safest amount source.
*/
        if (refundMap.containsKey('transactions') && refundMap.get('transactions') != null) {
            List<Object> transactions = (List<Object>) refundMap.get('transactions');
            
            for (Object transactionObj : transactions) {
                Map<String, Object> transactionMap =
                    (Map<String, Object>) transactionObj;
                
                if (transactionMap == null) {
                    continue;
                }
                
                String kind = getLowerString(transactionMap, 'kind');
                String status = getLowerString(transactionMap, 'status');
                
                if (
                    !String.isBlank(kind) &&
                    kind != 'refund'
                ) {
                    continue;
                }
                
                if (
                    !String.isBlank(status) &&
                    status != 'success'
                ) {
                    continue;
                }
                
                Decimal transactionAmount =
                    parseDecimalValue(transactionMap.get('amount'));
                
                if (transactionAmount != null) {
                    amount += transactionAmount;
                }
            }
        }
        
        if (amount > 0) {
            return amount;
        }
        
        /*
* Fallback for refund_line_items.
*/
        if (refundMap.containsKey('refund_line_items') && refundMap.get('refund_line_items') != null) {
            List<Object> refundLineItems =
                (List<Object>) refundMap.get('refund_line_items');
            
            for (Object refundLineItemObj : refundLineItems) {
                Map<String, Object> refundLineItemMap =
                    (Map<String, Object>) refundLineItemObj;
                
                if (refundLineItemMap == null) {
                    continue;
                }
                
                Decimal subtotal =
                    parseDecimalValue(refundLineItemMap.get('subtotal'));
                
                Decimal totalTax =
                    parseDecimalValue(refundLineItemMap.get('total_tax'));
                
                if (subtotal != null) {
                    amount += subtotal;
                }
                
                if (totalTax != null) {
                    amount += totalTax;
                }
            }
        }
        
        return amount > 0 ? amount : null;
    }
    
    private static String getFirstNonBlankValue(
        Map<String, Object> sourceMap,
        List<String> keys
    ) {
        if (sourceMap == null || keys == null) {
            return null;
        }
        
        for (String key : keys) {
            if (
                !String.isBlank(key) &&
                sourceMap.containsKey(key) &&
                sourceMap.get(key) != null &&
                !String.isBlank(String.valueOf(sourceMap.get(key)))
            ) {
                return String.valueOf(sourceMap.get(key));
            }
        }
        
        return null;
    }
    
    private static Decimal parseDecimalValue(Object rawValue) {
        if (rawValue == null) {
            return null;
        }
        
        try {
            return Decimal.valueOf(String.valueOf(rawValue));
        } catch (Exception e) {
            return null;
        }
    }
    
    private static Datetime parseShopifyDatetime(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }
        
        try {
            String escapedValue =
                rawValue.replace('\\', '\\\\').replace('"', '\\"');
            
            return (Datetime) JSON.deserialize(
                '"' + escapedValue + '"',
                Datetime.class
            );
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'OrderOrchestrationService: Unable to parse Shopify refund datetime. ' +
                'rawValue=' + rawValue +
                ', error=' + e.getMessage()
            );
            
            return null;
        }
    }
    
    public static void doNuancedMapping(Order thisOrder, Map<String, Object> payload) {
        if (thisOrder != null && payload != null) {
            thisOrder.Status = 'Draft';
            
            String salesChannel = deriveSalesChannel(payload);
            
            if (!String.isBlank(salesChannel)) {
                thisOrder.Sales_Channel__c = salesChannel;
            }
            
            // Always mark Shopify-created orders as Shopify Order
            thisOrder.Type = 'Shopify Order';
            
            // Implied Discount - amount only
            Decimal impliedDiscount = 0;
            
            if (payload.containsKey('total_discounts') &&
                payload.get('total_discounts') != null) {
                    
                    impliedDiscount =
                        Decimal.valueOf(String.valueOf(payload.get('total_discounts')));
                    
                } else if (payload.containsKey('current_total_discounts') &&
                           payload.get('current_total_discounts') != null) {
                               
                               impliedDiscount =
                                   Decimal.valueOf(
                                       String.valueOf(payload.get('current_total_discounts'))
                                   );
                               
                           } else if (payload.containsKey('implied_discount') &&
                                      payload.get('implied_discount') != null) {
                                          
                                          impliedDiscount =
                                              Decimal.valueOf(String.valueOf(payload.get('implied_discount')));
                                      }
            
            thisOrder.put('Implied_Discount__c', impliedDiscount);
            
            // Sales Channel - sync from Shopify only, do not default
            String shopifyChannel = null;
            
            if (payload.containsKey('source_name') &&
                payload.get('source_name') != null) {
                    
                    shopifyChannel = String.valueOf(payload.get('source_name')).trim();
                    
                } else if (payload.containsKey('sourceName') &&
                           payload.get('sourceName') != null) {
                               
                               shopifyChannel = String.valueOf(payload.get('sourceName')).trim();
                               
                           } else if (payload.containsKey('channel') &&
                                      payload.get('channel') != null) {
                                          
                                          shopifyChannel = String.valueOf(payload.get('channel')).trim();
                                      }
            
            if (!String.isBlank(shopifyChannel)) {
                String normalizedChannel = shopifyChannel.toLowerCase();
                
                if (normalizedChannel == 'web' ||
                    normalizedChannel == 'online_store' ||
                    normalizedChannel == 'online store') {
                        
                        thisOrder.put('Sales_Channel__c', 'Online Store');
                        
                    } else if (normalizedChannel == 'wb integration' ||
                               normalizedChannel == 'wb_integration') {
                                   
                                   thisOrder.put('Sales_Channel__c', 'WB Integration');
                                   
                               } else if (normalizedChannel == 'draft orders' ||
                                          normalizedChannel == 'draft_orders' ||
                                          normalizedChannel == 'draftorder' ||
                                          normalizedChannel == 'draft') {
                                              
                                              thisOrder.put('Sales_Channel__c', 'Draft Orders');
                                          }
            }
        }
    }
}