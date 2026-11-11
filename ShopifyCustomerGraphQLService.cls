public without sharing class ShopifyCustomerGraphQLService {
    
    @future(callout=true)
    public static void syncCustomersAsync(List<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }
        
        List<Account> accounts = [
            SELECT Id,
            FirstName,
            LastName,
            PersonEmail,
            Phone,
            Shop_ID__c,
            Updated_by_Integration__c
            FROM Account
            WHERE Id IN :accountIds
        ];
        
        for (Account acc : accounts) {
            syncSingleCustomer(acc);
        }
    }
    
    private static void syncSingleCustomer(Account acc) {
        if (acc == null) return;
        
        if (String.isBlank(acc.Shop_ID__c)) {
            createSingleCustomer(acc);
        } else {
            updateSingleCustomer(acc);
        }
    }
    
    private static void createSingleCustomer(Account acc) {
        String mutation =
            'mutation customerCreate($input: CustomerInput!) {' +
            '  customerCreate(input: $input) {' +
            '    customer { id firstName lastName email phone }' +
            '    userErrors { field message }' +
            '  }' +
            '}';
        
        Map<String, Object> input = new Map<String, Object>();
        if (!String.isBlank(acc.FirstName)) input.put('firstName', acc.FirstName);
        if (!String.isBlank(acc.LastName)) input.put('lastName', acc.LastName);
        if (!String.isBlank(acc.PersonEmail)) input.put('email', acc.PersonEmail);
        if (!String.isBlank(acc.Phone)) input.put('phone', acc.Phone);
        
        Map<String, Object> response = ShopifyGraphQLHelper.executeAllowPartialData(
            mutation,
            new Map<String, Object>{ 'input' => input }
        );
        
        Map<String, Object> customer = extractCustomerNode(response, 'customerCreate');
        if (customer != null && customer.get('id') != null) {
            String shopId = extractLegacyId(String.valueOf(customer.get('id')));
            update new Account(
                Id = acc.Id,
                Shop_ID__c = shopId
            );
        }
        
        validateUserErrorsOnly(response, 'customerCreate');
    }
    
    private static void updateSingleCustomer(Account acc) {
        String mutation =
            'mutation customerUpdate($input: CustomerInput!) {' +
            '  customerUpdate(input: $input) {' +
            '    customer { id firstName lastName email phone }' +
            '    userErrors { field message }' +
            '  }' +
            '}';
        
        Map<String, Object> input = new Map<String, Object>{
            'id' => ShopifyGraphQLHelper.toCustomerGid(acc.Shop_ID__c)
                };
                    
                    if (!String.isBlank(acc.FirstName)) input.put('firstName', acc.FirstName);
        if (!String.isBlank(acc.LastName)) input.put('lastName', acc.LastName);
        if (!String.isBlank(acc.PersonEmail)) input.put('email', acc.PersonEmail);
        if (!String.isBlank(acc.Phone)) input.put('phone', acc.Phone);
        
        Map<String, Object> response = ShopifyGraphQLHelper.executeAllowPartialData(
            mutation,
            new Map<String, Object>{ 'input' => input }
        );
        
        validateUserErrorsOnly(response, 'customerUpdate');
    }
    
    private static Map<String, Object> extractCustomerNode(Map<String, Object> response, String mutationName) {
        if (response == null || !response.containsKey('data')) return null;
        
        Map<String, Object> data = (Map<String, Object>) response.get('data');
        if (data == null || !data.containsKey(mutationName)) return null;
        
        Map<String, Object> mutationResult = (Map<String, Object>) data.get(mutationName);
        if (mutationResult == null || !mutationResult.containsKey('customer')) return null;
        
        return (Map<String, Object>) mutationResult.get('customer');
    }
    
    private static void validateUserErrorsOnly(Map<String, Object> response, String mutationName) {
        if (response == null || !response.containsKey('data')) {
            return;
        }
        
        Map<String, Object> data = (Map<String, Object>) response.get('data');
        if (data == null || !data.containsKey(mutationName)) {
            return;
        }
        
        Map<String, Object> mutationResult = (Map<String, Object>) data.get(mutationName);
        if (mutationResult == null) {
            return;
        }
        
        List<Object> userErrors = (List<Object>) mutationResult.get('userErrors');
        if (userErrors != null && !userErrors.isEmpty()) {
            throw new ShopifyGraphQLHelper.ShopifyGraphQLException(
                mutationName + ' userErrors: ' + JSON.serialize(userErrors)
            );
        }
    }
    
    private static String extractLegacyId(String gid) {
        if (String.isBlank(gid)) return null;
        return gid.substringAfterLast('/');
    }
    
    @future(callout=true)
    public static void syncCustomerLocalesAsync(List<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }
        
        List<Account> accounts = [
            SELECT Id,
            Shop_ID__c,
            Language__pc,
            Updated_by_Integration__c
            FROM Account
            WHERE Id IN :accountIds
        ];
        
        List<Account> accountsToUpdate = new List<Account>();
        
        for (Account acc : accounts) {
            if (acc == null || String.isBlank(acc.Shop_ID__c)) {
                continue;
            }
            
            String shopifyLocale = getCustomerLocale(acc.Shop_ID__c);
            
            if (String.isBlank(shopifyLocale)) {
                System.debug(LoggingLevel.INFO, 'No Shopify locale found for Account ' + acc.Id + ', Shopify Customer Id ' + acc.Shop_ID__c);
                continue;
            }
            
            String salesforceLanguage = mapShopifyLocaleToSalesforceLanguage(shopifyLocale);
            
            if (String.isBlank(salesforceLanguage)) {
                System.debug(LoggingLevel.INFO, 'No Salesforce language mapping found for Shopify locale: ' + shopifyLocale);
                continue;
            }
            
            Account accountUpdate = new Account(
                Id = acc.Id
            );
            
            accountUpdate.put('Language__pc', salesforceLanguage);
            accountUpdate.put('Updated_by_Integration__c', true);
            
            accountsToUpdate.add(accountUpdate);
        }
        
        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
    
    private static String getCustomerLocale(String shopifyCustomerId) {
        if (String.isBlank(shopifyCustomerId)) {
            return null;
        }
        
        String query =
            'query GetCustomerLocale($id: ID!) {' +
            '  customer(id: $id) {' +
            '    id ' +
            '    legacyResourceId ' +
            '    locale ' +
            '  }' +
            '}';
        
        Map<String, Object> response = ShopifyGraphQLHelper.executeAllowPartialData(
            query,
            new Map<String, Object>{
                'id' => ShopifyGraphQLHelper.toCustomerGid(shopifyCustomerId)
                    }
        );
        
        if (response == null || !response.containsKey('data')) {
            return null;
        }
        
        Map<String, Object> data = (Map<String, Object>) response.get('data');
        
        if (data == null || !data.containsKey('customer') || data.get('customer') == null) {
            return null;
        }
        
        Map<String, Object> customer = (Map<String, Object>) data.get('customer');
        
        if (customer.containsKey('locale') && customer.get('locale') != null) {
            return String.valueOf(customer.get('locale')).trim();
        }
        
        return null;
    }
    private static String mapShopifyLocaleToSalesforceLanguage(String locale) {
        if (String.isBlank(locale)) {
            return null;
        }
        
        String normalizedLocale = locale.trim().toLowerCase();
        
        if (normalizedLocale.startsWith('en')) {
            return 'English';
        }
        
        if (normalizedLocale.startsWith('fr')) {
            return 'French';
        }
        
        if (normalizedLocale.startsWith('de')) {
            return 'German';
        }
        
        if (normalizedLocale.startsWith('es')) {
            return 'Spanish';
        }
        
        return null;
    }   
}