public class ShopifyCollectionGraphQLService {
    
    private static final String NC = 'callout:Shopify_Admin_API';
    private static final String API_VERSION = '2026-04';
    public static Boolean bypassCollectionTrigger = false;
    public static Boolean bypassProductCollectionTrigger = false;
    
    /*
* =========================
* PUBLIC ENTRY METHODS
* =========================
*/
    
    @future(callout=true)
    public static void syncCollectionAsync(Id collectionId) {
        if (collectionId == null) return;
        
        Collection__c c = [
            SELECT Id,
            Name,
            Description__c,
            Manual__c,
            Smart__c,
            Shopify_Collection_Id__c
            FROM Collection__c
            WHERE Id = :collectionId
            LIMIT 1
        ];
        
        if (String.isBlank(c.Shopify_Collection_Id__c)) {
            createCollection(c);
        } else {
            updateCollection(c);
        }
    }
    
    @future(callout=true)
    public static void addProductToCollectionAsync(Id productCollectionId) {
        if (productCollectionId == null) return;
        
        Product_Collection__c pc = [
            SELECT Id,
            Product__c,
            Product__r.Shop_ID__c,
            Collection__c,
            Collection__r.Shopify_Collection_Id__c
            FROM Product_Collection__c
            WHERE Id = :productCollectionId
            LIMIT 1
        ];
        
        if (pc.Product__r == null || String.isBlank(pc.Product__r.Shop_ID__c)) return;
        if (pc.Collection__r == null || String.isBlank(pc.Collection__r.Shopify_Collection_Id__c)) return;
        
        String mutation =
            'mutation AddProducts($id: ID!, $productIds: [ID!]!) {' +
            '  collectionAddProducts(id: $id, productIds: $productIds) {' +
            '    userErrors { field message }' +
            '  }' +
            '}';
        
        Map<String, Object> variables = new Map<String, Object>{
            'id' => toGid('Collection', pc.Collection__r.Shopify_Collection_Id__c),
                'productIds' => new List<Object>{
                    toGid('Product', pc.Product__r.Shop_ID__c)
                        }
        };
            
            Map<String, Object> response = executeGraphQL(mutation, variables);
        assertNoTopLevelErrors(response);
        assertNoUserErrors(response, 'collectionAddProducts');
    }
    
    @future(callout=true)
    public static void removeProductFromCollectionAsync(String collectionShopId, String productShopId) {
        if (String.isBlank(collectionShopId) || String.isBlank(productShopId)) return;
        
        String mutation =
            'mutation RemoveProducts($id: ID!, $productIds: [ID!]!) {' +
            '  collectionRemoveProducts(id: $id, productIds: $productIds) {' +
            '    userErrors { field message }' +
            '  }' +
            '}';
        
        Map<String, Object> variables = new Map<String, Object>{
            'id' => toGid('Collection', collectionShopId),
                'productIds' => new List<Object>{
                    toGid('Product', productShopId)
                        }
        };
            
            Map<String, Object> response = executeGraphQL(mutation, variables);
        assertNoTopLevelErrors(response);
        assertNoUserErrors(response, 'collectionRemoveProducts');
    }
    
    @future(callout=true)
    public static void pullCollectionAsync(String collectionShopId) {
        if (String.isBlank(collectionShopId)) return;
        
        String query =
            'query GetCollection($id: ID!) {' +
            '  collection(id: $id) {' +
            '    id title handle descriptionHtml ' +
            '    ruleSet { appliedDisjunctively rules { column relation condition } } ' +
            '    products(first: 250) { nodes { id legacyResourceId title } } ' +
            '  }' +
            '}';
        
        Map<String, Object> variables = new Map<String, Object>{
            'id' => 'gid://shopify/Collection/' + collectionShopId
                };
                    
                    Map<String, Object> response = executeGraphQL(query, variables);
        assertNoTopLevelErrors(response);
        
        Map<String, Object> dataMap = (Map<String, Object>) response.get('data');
        if (dataMap == null) return;
        
        Map<String, Object> collectionNode = (Map<String, Object>) dataMap.get('collection');
        if (collectionNode == null) return;
        
        upsertCollectionFromShopify(collectionNode);
    }
    
    /*
* =========================
* INBOUND UPSERT LOGIC
* =========================
*/
    
    public static void upsertCollectionFromShopify(Map<String, Object> collectionNode) {
        if (collectionNode == null) return;
        
        String shopId = extractNumericId((String) collectionNode.get('id'));
        if (String.isBlank(shopId)) return;
        
        List<Collection__c> existing = [
            SELECT Id
            FROM Collection__c
            WHERE Shopify_Collection_Id__c = :shopId
            LIMIT 1
        ];
        
        Collection__c target = existing.isEmpty()
            ? new Collection__c()
            : existing[0];
        
        target.Shopify_Collection_Id__c = shopId;
        target.Name = (String) collectionNode.get('title');
        String rawDescriptionHtml = (String) collectionNode.get('descriptionHtml');
        
        target.Description_HTML__c = rawDescriptionHtml;
        target.Description__c = stripHtmlToText(rawDescriptionHtml);
        
        Map<String, Object> ruleSet = (Map<String, Object>) collectionNode.get('ruleSet');
        target.Smart__c = ruleSet != null;
        target.Manual__c = ruleSet == null;
        
        bypassCollectionTrigger = true;
        try {
            if (target.Id == null) {
                insert target;
            } else {
                update target;
            }
        } finally {
            bypassCollectionTrigger = false;
        }
        
        syncMembershipFromShopify(target.Id, collectionNode);
    }
    
    private static void syncMembershipFromShopify(Id collectionId, Map<String, Object> collectionNode) {
        if (collectionId == null || collectionNode == null) return;
        
        Collection__c col = [
            SELECT Id, Shopify_Collection_Id__c
            FROM Collection__c
            WHERE Id = :collectionId
            LIMIT 1
        ];
        
        Map<String, Object> productsMap = (Map<String, Object>) collectionNode.get('products');
        if (productsMap == null) return;
        
        List<Object> nodes = (List<Object>) productsMap.get('nodes');
        if (nodes == null) nodes = new List<Object>();
        
        Set<String> incomingProductShopIds = new Set<String>();
        
        for (Object obj : nodes) {
            Map<String, Object> p = (Map<String, Object>) obj;
            if (p == null || p.get('legacyResourceId') == null) continue;
            
            incomingProductShopIds.add(String.valueOf(p.get('legacyResourceId')));
        }
        
        Map<String, Product2> productsByShopId = new Map<String, Product2>();
        if (!incomingProductShopIds.isEmpty()) {
            for (Product2 p : [
                SELECT Id, Shop_ID__c
                FROM Product2
                WHERE Shop_ID__c IN :incomingProductShopIds
            ]) {
                productsByShopId.put(p.Shop_ID__c, p);
            }
        }
        
        List<Product_Collection__c> existingRows = [
            SELECT Id, External_key__c
            FROM Product_Collection__c
            WHERE Collection__c = :collectionId
        ];
        
        Map<String, Product_Collection__c> existingByKey = new Map<String, Product_Collection__c>();
        for (Product_Collection__c row : existingRows) {
            existingByKey.put(row.External_key__c, row);
        }
        
        Set<String> incomingKeys = new Set<String>();
        List<Product_Collection__c> toInsert = new List<Product_Collection__c>();
        
        for (String productShopId : incomingProductShopIds) {
            Product2 sfProduct = productsByShopId.get(productShopId);
            if (sfProduct == null) continue;
            
            String key = productShopId + '-' + col.Shopify_Collection_Id__c;
            incomingKeys.add(key);
            
            if (!existingByKey.containsKey(key)) {
                Product_Collection__c pc = new Product_Collection__c();
                pc.Product__c = sfProduct.Id;
                pc.Collection__c = col.Id;
                pc.External_key__c = key;
                toInsert.add(pc);
            }
        }
        
        List<Product_Collection__c> toDelete = new List<Product_Collection__c>();
        for (Product_Collection__c row : existingRows) {
            if (!incomingKeys.contains(row.External_key__c)) {
                toDelete.add(row);
            }
        }
        
        bypassProductCollectionTrigger = true;
        try {
            if (!toInsert.isEmpty()) insert toInsert;
            if (!toDelete.isEmpty()) delete toDelete;
        } finally {
            bypassProductCollectionTrigger = false;
        }
    }
    
    /*
* =========================
* OUTBOUND COLLECTION LOGIC
* =========================
*/
    
    private static void createCollection(Collection__c c) {
        String mutation =
            'mutation CreateCollection($input: CollectionInput!) {' +
            '  collectionCreate(input: $input) {' +
            '    collection { id title handle descriptionHtml } ' +
            '    userErrors { field message } ' +
            '  } ' +
            '}';
        
        Map<String, Object> input = new Map<String, Object>{
            'title' => c.Name,
                'descriptionHtml' => c.Description__c
                };
                    
                    Map<String, Object> response = executeGraphQL(
                        mutation,
                        new Map<String, Object>{ 'input' => input }
                    );
        
        assertNoTopLevelErrors(response);
        assertNoUserErrors(response, 'collectionCreate');
        
        Map<String, Object> dataMap = (Map<String, Object>) response.get('data');
        Map<String, Object> wrapper = (Map<String, Object>) dataMap.get('collectionCreate');
        Map<String, Object> created = (Map<String, Object>) wrapper.get('collection');
        
        String shopId = extractNumericId((String) created.get('id'));
        
        Collection__c updateRow = new Collection__c(
            Id = c.Id,
            Shopify_Collection_Id__c = shopId
        );
        update updateRow;
    }
    
    private static void updateCollection(Collection__c c) {
        String mutation =
            'mutation UpdateCollection($input: CollectionInput!) {' +
            '  collectionUpdate(input: $input) {' +
            '    collection { id title handle descriptionHtml } ' +
            '    userErrors { field message } ' +
            '  } ' +
            '}';
        
        Map<String, Object> input = new Map<String, Object>{
            'id' => toGid('Collection', c.Shopify_Collection_Id__c),
                'title' => c.Name,
                'descriptionHtml' => c.Description__c
                };
                    
                    Map<String, Object> response = executeGraphQL(
                        mutation,
                        new Map<String, Object>{ 'input' => input }
                    );
        
        assertNoTopLevelErrors(response);
        assertNoUserErrors(response, 'collectionUpdate');
    }
    
    /*
* =========================
* LOW-LEVEL HELPERS
* =========================
*/
    
    private static Map<String, Object> executeGraphQL(String query, Map<String, Object> variables) {
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint(NC + '/admin/api/' + API_VERSION + '/graphql.json');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);
        
        Map<String, Object> body = new Map<String, Object>{
            'query' => query,
                'variables' => variables
                };
                    
                    req.setBody(JSON.serialize(body));
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException(
                'Shopify GraphQL HTTP error. Status=' + res.getStatusCode() + ', body=' + res.getBody()
            );
        }
        
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }
    
    private static void assertNoTopLevelErrors(Map<String, Object> response) {
        if (response == null) {
            throw new AuraHandledException('Shopify GraphQL returned null response.');
        }
        
        List<Object> errors = (List<Object>) response.get('errors');
        if (errors != null && !errors.isEmpty()) {
            throw new AuraHandledException('Shopify GraphQL errors: ' + JSON.serialize(errors));
        }
    }
    
    private static void assertNoUserErrors(Map<String, Object> response, String operationName) {
        if (response == null) return;
        
        Map<String, Object> dataMap = (Map<String, Object>) response.get('data');
        if (dataMap == null) return;
        
        Map<String, Object> opMap = (Map<String, Object>) dataMap.get(operationName);
        if (opMap == null) return;
        
        List<Object> userErrors = (List<Object>) opMap.get('userErrors');
        if (userErrors != null && !userErrors.isEmpty()) {
            throw new AuraHandledException(operationName + ' userErrors: ' + JSON.serialize(userErrors));
        }
    }
    
    private static String toGid(String objectName, String numericId) {
        return 'gid://shopify/' + objectName + '/' + numericId;
    }
    
    public static String extractNumericId(String gid) {
        if (String.isBlank(gid)) return null;
        List<String> parts = gid.split('/');
        return parts.isEmpty() ? null : parts[parts.size() - 1];
    }
    
    //HTML to text stripping method
    private static String stripHtmlToText(String htmlValue) {
    if (String.isBlank(htmlValue)) return null;

    String textValue = htmlValue;

    // Preserve basic line breaks before removing all HTML tags
    textValue = textValue.replaceAll('(?i)<br\\s*/?>', '\n');
    textValue = textValue.replaceAll('(?i)</p\\s*>', '\n');

    // Remove all remaining HTML tags
    textValue = textValue.replaceAll('<[^>]+>', '');

    // Decode common HTML entities
    textValue = textValue.unescapeHtml4();

    // Clean spacing
    textValue = textValue.replaceAll('[\\t\\r ]+', ' ');
    textValue = textValue.replaceAll(' *\\n *', '\n');
    textValue = textValue.replaceAll('\\n{3,}', '\n\n');

    return textValue.trim();
}
}