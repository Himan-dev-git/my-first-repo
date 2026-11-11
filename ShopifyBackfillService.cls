public without sharing class ShopifyBackfillService {
    
    private static final String NAMED_CREDENTIAL =
        'callout:Shopify_Admin_API';
    
    private static final String API_VERSION =
        '2026-04';
    private static final Integer PAGE_SIZE = 5;
    private static final Integer ORDER_PAGE_SIZE = 5;
    private static final Integer PRODUCT_PAGE_SIZE = 25;
    private static final Integer INVENTORY_PAGE_SIZE = 25;
    
    private static final String TYPE_ORDERS =
        'ORDERS';
    
    private static final String TYPE_CUSTOM_COLLECTIONS =
        'CUSTOM_COLLECTIONS';
    
    private static final String TYPE_SMART_COLLECTIONS =
        'SMART_COLLECTIONS';
    
    private static final String TYPE_INVENTORY =
        'INVENTORY';
    
    /*
* ============================================================
* PRODUCTS
* ============================================================
*/
    
public static Id backfillProducts() {

    return Database.executeBatch(
        new ShopifyProductPageBatch(),
        1
    );
}
    
    /*
* ============================================================
* ORDERS
* ============================================================
*/
    
    public static Id backfillOrders() {
        String endpoint = buildEndpoint(
            '/orders.json',
            new Map<String, String>{
                'limit' =>
                    String.valueOf(ORDER_PAGE_SIZE),
                    
                    'status' =>
                    'any',
                    
                    'order' =>
                    'created_at asc',
                    
                    /*
* Start from the beginning of the accessible
* Shopify order history.
*/
                    'since_id' =>
                    '0'
                    }
        );
        
        return System.enqueueJob(
            new ShopifyBackfillQueueable(
                TYPE_ORDERS,
                endpoint
            )
        );
    }
    
    public static Id backfillOrdersFrom(
        Datetime createdAtMin
    ) {
        if (createdAtMin == null) {
            return backfillOrders();
        }
        
        String endpoint = buildEndpoint(
            '/orders.json',
            new Map<String, String>{
                'limit' =>
                    String.valueOf(ORDER_PAGE_SIZE),
                    
                    'status' =>
                    'any',
                    
                    'order' =>
                    'created_at asc',
                    
                    'created_at_min' =>
                    formatShopifyDatetime(
                        createdAtMin
                    ),
                    
                    'since_id' =>
                    '0'
                    }
        );
        
        return System.enqueueJob(
            new ShopifyBackfillQueueable(
                TYPE_ORDERS,
                endpoint
            )
        );
    }
    
    public static Id backfillOrdersBetween(
        Datetime createdAtMin,
        Datetime createdAtMax
    ) {
        if (
            createdAtMin == null ||
            createdAtMax == null
        ) {
            throw new ShopifyBackfillException(
                'Both createdAtMin and createdAtMax are required.'
            );
        }
        
        if (createdAtMax <= createdAtMin) {
            throw new ShopifyBackfillException(
                'createdAtMax must be later than createdAtMin.'
            );
        }
        
        String endpoint = buildEndpoint(
            '/orders.json',
            new Map<String, String>{
                'limit' =>
                    String.valueOf(ORDER_PAGE_SIZE),
                    
                    'status' => 'any',
                    
                    'order' =>
                    'created_at asc',
                    
                    'created_at_min' =>
                    formatShopifyDatetime(
                        createdAtMin
                    ),
                    
                    'created_at_max' =>
                    formatShopifyDatetime(
                        createdAtMax
                    ),
                    
                    'since_id' =>
                    '0'
                    }
        );
        
        return System.enqueueJob(
            new ShopifyBackfillQueueable(
                TYPE_ORDERS,
                endpoint
            )
        );
    }
    
    /*
* ============================================================
* COLLECTIONS
* ============================================================
*/
    
    public static List<Id> backfillCollections() {
        List<Id> jobIds = new List<Id>();
        
        String customEndpoint = buildEndpoint(
            '/custom_collections.json',
            new Map<String, String>{
                'limit' =>
                    String.valueOf(PAGE_SIZE)
                    }
        );
        
        String smartEndpoint = buildEndpoint(
            '/smart_collections.json',
            new Map<String, String>{
                'limit' =>
                    String.valueOf(PAGE_SIZE)
                    }
        );
        
        jobIds.add(
            System.enqueueJob(
                new ShopifyBackfillQueueable(
                    TYPE_CUSTOM_COLLECTIONS,
                    customEndpoint
                )
            )
        );
        
        jobIds.add(
            System.enqueueJob(
                new ShopifyBackfillQueueable(
                    TYPE_SMART_COLLECTIONS,
                    smartEndpoint
                )
            )
        );
        
        return jobIds;
    }
    
    /*
* ============================================================
* INVENTORY
* ============================================================
*/
    
    public static List<Id> backfillInventory() {
        Set<String> inventoryItemIds =
            new Set<String>();
        
        for (Product2 variant : [
            SELECT Inventory_Item_Id__c
            FROM Product2
            WHERE Inventory_Item_Id__c != null
            AND Type__c = 'Variant'
        ]) {
            String inventoryItemId =
                extractNumericId(
                    variant.Inventory_Item_Id__c
                );
            
            if (!String.isBlank(inventoryItemId)) {
                inventoryItemIds.add(
                    inventoryItemId
                );
            }
        }
        
        if (inventoryItemIds.isEmpty()) {
            throw new ShopifyBackfillException(
                'No variants with Inventory_Item_Id__c were found.'
            );
        }
        
        List<String> allIds =
            new List<String>();
        
        allIds.addAll(inventoryItemIds);
        
        List<Id> jobIds =
            new List<Id>();
        
        Integer chunkSize = INVENTORY_PAGE_SIZE;
        
        for (
            Integer startIndex = 0;
            startIndex < allIds.size();
            startIndex += chunkSize
        ) {
            Integer endIndex =
                Math.min(
                    startIndex + chunkSize,
                    allIds.size()
                );
            
            List<String> currentChunk =
                new List<String>();
            
            for (
                Integer index = startIndex;
                index < endIndex;
                index++
            ) {
                currentChunk.add(
                    allIds[index]
                );
            }
            
            String endpoint = buildEndpoint(
                '/inventory_levels.json',
                new Map<String, String>{
                    'limit' =>
                        String.valueOf(INVENTORY_PAGE_SIZE),
                        
                        'inventory_item_ids' =>
                        String.join(
                            currentChunk,
                            ','
                        )
                        }
            );
            
            jobIds.add(
                System.enqueueJob(
                    new ShopifyBackfillQueueable(
                        TYPE_INVENTORY,
                        endpoint
                    )
                )
            );
        }
        
        return jobIds;
    }
    
    /*
* ============================================================
* Sales Insight Migration
* ============================================================
*/
    
    
    public static Id refreshProductSalesInsights() {
        return Database.executeBatch(
            new ProductSalesInsightMigrationBatch(),
            50
        );
    }
    
    /*
* ============================================================
* QUEUEABLE FOR NON-PRODUCT ENTITIES
* ============================================================
*/
    
    public class ShopifyBackfillQueueable
        implements Queueable, Database.AllowsCallouts {
            
            private String backfillType;
            private String endpoint;
            private Long previousOrderSinceId;
            
            public ShopifyBackfillQueueable(
                String backfillType,
                String endpoint
            ) {
                this.backfillType =
                    backfillType;
                
                this.endpoint =
                    endpoint;
                
                this.previousOrderSinceId =
                    extractSinceId(
                        endpoint
                    );
            }
            
            public void execute(
                QueueableContext context
            ) {
                if (String.isBlank(backfillType)) {
                    throw new ShopifyBackfillException(
                        'Backfill type is required.'
                    );
                }
                
                if (String.isBlank(endpoint)) {
                    throw new ShopifyBackfillException(
                        'Shopify endpoint is required.'
                    );
                }
                
                HttpResponse response;
                
                try {
                    response = sendRequest(endpoint);
                } catch (Exception requestException) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'Shopify backfill request failed. ' +
                        'BackfillType=' + backfillType +
                        ', Endpoint=' + endpoint +
                        ', Error=' +
                        requestException.getMessage() +
                        ', StackTrace=' +
                        requestException.getStackTraceString()
                    );
                    
                    return;
                }
                
                Map<String, Object> responsePayload;
                
                try {
                    responsePayload =
                        deserializeResponse(response);
                } catch (Exception deserializeException) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'Shopify backfill response could not be deserialized. ' +
                        'BackfillType=' + backfillType +
                        ', Endpoint=' + endpoint +
                        ', Status=' + response.getStatusCode() +
                        ', Body=' + response.getBody() +
                        ', Error=' +
                        deserializeException.getMessage()
                    );
                    
                    return;
                }
                
                String nextEndpoint;
                
                if (backfillType == TYPE_ORDERS) {
                    nextEndpoint =
                        buildNextOrderEndpoint(
                            endpoint,
                            responsePayload
                        );
                } else {
                    nextEndpoint =
                        getNextEndpoint(
                            response.getHeader('Link')
                        );
                }
                
                try {
                    processPayload(
                        backfillType,
                        responsePayload
                    );
                } catch (Exception processingException) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'Shopify backfill page processing failed. ' +
                        'BackfillType=' + backfillType +
                        ', Endpoint=' + endpoint +
                        ', Error=' +
                        processingException.getMessage() +
                        ', StackTrace=' +
                        processingException.getStackTraceString()
                    );
                    
                    return;
                }
                
                if (backfillType == TYPE_ORDERS) {
                    Long nextSinceId =
                        extractSinceId(nextEndpoint);
                    
                    if (
                        nextSinceId != null &&
                        previousOrderSinceId != null &&
                        nextSinceId <= previousOrderSinceId
                    ) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'Shopify order backfill stopped because since_id did not advance. ' +
                            'PreviousSinceId=' + previousOrderSinceId +
                            ', NextSinceId=' + nextSinceId
                        );
                        
                        nextEndpoint = null;
                    }
                }
                
                if (!String.isBlank(nextEndpoint)) {
                    System.enqueueJob(
                        new ShopifyBackfillQueueable(
                            backfillType,
                            nextEndpoint
                        )
                    );
                }
            }
        }
    
    /*
* ============================================================
* PAYLOAD PROCESSING
* ============================================================
*/
    
    @TestVisible
    private static Long extractSinceId(
        String endpoint
    ) {
        if (String.isBlank(endpoint)) {
            return null;
        }
        
        Matcher matcher =
            Pattern.compile(
                '[?&]since_id=([0-9]+)'
            ).matcher(endpoint);
        
        if (!matcher.find()) {
            return null;
        }
        
        try {
            return Long.valueOf(
                matcher.group(1)
            );
        } catch (Exception conversionException) {
            return null;
        }
    }
    
    @TestVisible
    private static String buildNextOrderEndpoint(
        String currentEndpoint,
        Map<String, Object> responsePayload
    ) {
        if (responsePayload == null) {
            return null;
        }
        
        List<Object> orders =
            getObjectList(
                responsePayload,
                'orders'
            );
        
        if (orders.isEmpty()) {
            return null;
        }
        
        Long highestOrderId;
        
        for (Object rawOrder : orders) {
            Map<String, Object> orderMap =
                castToMap(rawOrder);
            
            if (
                orderMap == null ||
                orderMap.get('id') == null
            ) {
                continue;
            }
            
            try {
                Long currentOrderId =
                    Long.valueOf(
                        String.valueOf(
                            orderMap.get('id')
                        )
                    );
                
                if (
                    highestOrderId == null ||
                    currentOrderId > highestOrderId
                ) {
                    highestOrderId =
                        currentOrderId;
                }
            } catch (Exception conversionException) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Could not parse Shopify order ID. Value=' +
                    String.valueOf(orderMap.get('id'))
                );
            }
        }
        
        if (
            highestOrderId == null ||
            orders.size() < ORDER_PAGE_SIZE
        ) {
            return null;
        }
        
        Map<String, String> queryParameters =
            new Map<String, String>{
                'limit' =>
                    String.valueOf(ORDER_PAGE_SIZE),
                    'status' =>
                    'any',
                    'order' =>
                    'created_at asc',
                    'since_id' =>
                    String.valueOf(highestOrderId)
                    };
                        
                        String createdAtMin =
                        getQueryParameter(
                            currentEndpoint,
                            'created_at_min'
                        );
        
        if (!String.isBlank(createdAtMin)) {
            queryParameters.put(
                'created_at_min',
                createdAtMin
            );
        }
        
        String createdAtMax =
            getQueryParameter(
                currentEndpoint,
                'created_at_max'
            );
        
        if (!String.isBlank(createdAtMax)) {
            queryParameters.put(
                'created_at_max',
                createdAtMax
            );
        }
        
        return buildEndpoint(
            '/orders.json',
            queryParameters
        );
    }
    
    @TestVisible
    private static String getQueryParameter(
        String endpoint,
        String parameterName
    ) {
        if (
            String.isBlank(endpoint) ||
            String.isBlank(parameterName) ||
            !endpoint.contains('?')
        ) {
            return null;
        }
        
        String queryString =
            endpoint.substringAfter('?');
        
        for (String queryPart : queryString.split('&')) {
            if (String.isBlank(queryPart)) {
                continue;
            }
            
            Integer equalsPosition =
                queryPart.indexOf('=');
            
            if (equalsPosition <= 0) {
                continue;
            }
            
            String key =
                EncodingUtil.urlDecode(
                    queryPart.substring(0, equalsPosition),
                    'UTF-8'
                );
            
            if (key != parameterName) {
                continue;
            }
            
            return EncodingUtil.urlDecode(
                queryPart.substring(equalsPosition + 1),
                'UTF-8'
            );
        }
        
        return null;
    }
    
    private static void processPayload(
        String backfillType,
        Map<String, Object> payload
    ) {
        if (payload == null) {
            return;
        }
        
        if (backfillType == TYPE_ORDERS) {
            processOrders(payload);
            return;
        }
        
        if (
            backfillType ==
            TYPE_CUSTOM_COLLECTIONS
        ) {
            processCollections(
                payload,
                'custom_collections'
            );
            
            return;
        }
        
        if (
            backfillType ==
            TYPE_SMART_COLLECTIONS
        ) {
            processCollections(
                payload,
                'smart_collections'
            );
            
            return;
        }
        
        if (backfillType == TYPE_INVENTORY) {
            processInventoryLevels(payload);
            return;
        }
        
        throw new ShopifyBackfillException(
            'Unsupported backfill type: ' +
            backfillType
        );
    }
    
    private static void processOrders(
        Map<String, Object> payload
    ) {
        List<Object> orders =
            getObjectList(
                payload,
                'orders'
            );
        
        if (orders.isEmpty()) {
            System.debug(
                LoggingLevel.INFO,
                'Shopify order backfill returned no orders.'
            );
            
            return;
        }
        
        for (Object rawOrder : orders) {
            Map<String, Object> orderMap =
                castToMap(rawOrder);
            
            if (orderMap == null) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Shopify order backfill skipped an invalid order payload. ' +
                    'Payload=' + JSON.serialize(rawOrder)
                );
                
                continue;
            }
            
            String shopifyOrderId =
                orderMap.get('id') == null
                ? null
                : String.valueOf(
                    orderMap.get('id')
                );
            
            try {
                /*
* Use the singular-order path, matching the
* successful Execute Anonymous test.
*/
                OrderOrchestrationService.processOrdersFromRestRequest(
                    new Map<String, Object>{
                        'order' => orderMap
                            },
                    new String[]{
                        'orders',
                            'order_items',
                            'fulfillments'
                            }
                );
                
                System.debug(
                    LoggingLevel.INFO,
                    'Shopify historical order processed successfully. ' +
                    'ShopifyOrderId=' +
                    shopifyOrderId
                );
            } catch (Exception orderException) {
                /*
* Skip only this order. Do not stop the complete
* historical order migration.
*/
                System.debug(
                    LoggingLevel.ERROR,
                    'Shopify historical order failed. ' +
                    'ShopifyOrderId=' +
                    shopifyOrderId +
                    ', Error=' +
                    orderException.getMessage() +
                    ', StackTrace=' +
                    orderException.getStackTraceString()
                );
            }
        }
    }
    
    private static void processCollections(
        Map<String, Object> payload,
        String propertyName
    ) {
        List<Object> collections =
            getObjectList(
                payload,
                propertyName
            );
        
        for (Object collectionObject : collections) {
            Map<String, Object> collectionPayload =
                castToMap(collectionObject);
            
            if (collectionPayload == null) {
                continue;
            }
            
            CollectionOrchestrationService.processCollectionWebhook(
                collectionPayload
            );
        }
    }
    
    private static void processInventoryLevels(
        Map<String, Object> payload
    ) {
        List<Object> inventoryLevels =
            getObjectList(
                payload,
                'inventory_levels'
            );
        
        for (
            Object inventoryLevelObject :
            inventoryLevels
        ) {
            Map<String, Object> inventoryPayload =
                castToMap(
                    inventoryLevelObject
                );
            
            if (inventoryPayload == null) {
                continue;
            }
            
            InventoryLevelOrchestrationService.processInventoryLevelWebhook(
                inventoryPayload
            );
        }
    }
    
    /*
* ============================================================
* HTTP
* ============================================================
*/
    
    private static HttpResponse sendRequest(
        String endpoint
    ) {
        HttpRequest request = new HttpRequest();
        
        request.setMethod('GET');
        request.setEndpoint(endpoint);
        request.setHeader(
            'Accept',
            'application/json'
        );
        request.setTimeout(120000);
        
        HttpResponse response =
            new Http().send(request);
        
        Integer statusCode =
            response.getStatusCode();
        
        if (
            statusCode < 200 ||
            statusCode >= 300
        ) {
            throw new ShopifyBackfillException(
                'Shopify backfill callout failed. ' +
                'Status=' + statusCode +
                ', Endpoint=' + endpoint +
                ', Body=' + response.getBody()
            );
        }
        
        return response;
    }
    
    private static Map<String, Object>
        deserializeResponse(
            HttpResponse response
        ) {
            if (response == null) {
                throw new ShopifyBackfillException(
                    'Shopify returned a null HTTP response.'
                );
            }
            
            if (String.isBlank(response.getBody())) {
                return new Map<String, Object>();
            }
            
            Map<String, Object> result =
                castToMap(
                    JSON.deserializeUntyped(
                        response.getBody()
                    )
                );
            
            if (result == null) {
                throw new ShopifyBackfillException(
                    'Unexpected Shopify response: ' +
                    response.getBody()
                );
            }
            
            return result;
        }
    
    /*
* ============================================================
* PAGINATION
* ============================================================
*/
    
    @TestVisible
    private static String getNextEndpoint(
        String linkHeader
    ) {
        if (String.isBlank(linkHeader)) {
            return null;
        }
        
        for (String linkValue : linkHeader.split(',')) {
            if (
                String.isBlank(linkValue) ||
                !linkValue.contains('rel="next"')
            ) {
                continue;
            }
            
            Integer startPosition =
                linkValue.indexOf('<');
            
            Integer endPosition =
                linkValue.indexOf('>');
            
            if (
                startPosition < 0 ||
                endPosition <= startPosition
            ) {
                continue;
            }
            
            String fullUrl =
                linkValue.substring(
                    startPosition + 1,
                    endPosition
                );
            
            Integer adminPathPosition =
                fullUrl.indexOf('/admin/api/');
            
            if (adminPathPosition < 0) {
                continue;
            }
            
            return NAMED_CREDENTIAL +
                fullUrl.substring(
                    adminPathPosition
                );
        }
        
        return null;
    }
    
    /*
* ============================================================
* HELPERS
* ============================================================
*/
    
    private static String buildEndpoint(
        String resourcePath,
        Map<String, String> queryParameters
    ) {
        String endpoint =
            NAMED_CREDENTIAL +
            '/admin/api/' +
            API_VERSION +
            resourcePath;
        
        if (
            queryParameters == null ||
            queryParameters.isEmpty()
        ) {
            return endpoint;
        }
        
        List<String> queryParts =
            new List<String>();
        
        for (
            String parameterName :
            queryParameters.keySet()
        ) {
            String parameterValue =
                queryParameters.get(
                    parameterName
                );
            
            if (
                String.isBlank(parameterName) ||
                parameterValue == null
            ) {
                continue;
            }
            
            queryParts.add(
                EncodingUtil.urlEncode(
                    parameterName,
                    'UTF-8'
                ) +
                '=' +
                EncodingUtil.urlEncode(
                    parameterValue,
                    'UTF-8'
                )
            );
        }
        
        if (!queryParts.isEmpty()) {
            endpoint +=
                '?' +
                String.join(
                    queryParts,
                    '&'
                );
        }
        
        return endpoint;
    }
    
    private static List<Object> getObjectList(
        Map<String, Object> payload,
        String propertyName
    ) {
        if (
            payload == null ||
            String.isBlank(propertyName) ||
            !payload.containsKey(propertyName)
        ) {
            return new List<Object>();
        }
        
        try {
            return (List<Object>)
                payload.get(propertyName);
        } catch (Exception e) {
            return new List<Object>();
        }
    }
    
    private static Map<String, Object> castToMap(
        Object rawValue
    ) {
        if (rawValue == null) {
            return null;
        }
        
        try {
            return (Map<String, Object>) rawValue;
        } catch (Exception e) {
            return null;
        }
    }
    
    private static String extractNumericId(
        String rawId
    ) {
        if (String.isBlank(rawId)) {
            return null;
        }
        
        String cleanedId = rawId.trim();
        
        if (cleanedId.contains('/')) {
            List<String> parts =
                cleanedId.split('/');
            
            cleanedId =
                parts[parts.size() - 1];
        }
        
        return cleanedId;
    }
    
    private static String formatShopifyDatetime(
        Datetime value
    ) {
        return value.formatGMT(
            'yyyy-MM-dd\'T\'HH:mm:ss\'Z\''
        );
    }
    
    public class ShopifyBackfillException
        extends Exception {
        }
    
    public static Id backfillGeneratedSkus() {
        /*
* Pushes existing Salesforce SKUs to Shopify.
* Does not change Salesforce SKUs.
*/
        return Database.executeBatch(
            new ShopifyGeneratedSkuBackfillBatch(false),
            25
        );
    }
    
    public static Id regenerateAllProductSkus() {
        return Database.executeBatch(
            new ShopifyGeneratedSkuBackfillBatch(
                'CLEAR_ALL'
            ),
            25
        );
    }
}