public class AccountOrchestrationService {
    
    // Static variable to hold the default customer account
    public static Account defaultCustomerAccount;
    
    // Static variable for Person Account RecordTypeId
    public static Id personAccountRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1].Id;
    
    public static void processCustomersFromRestRequest(Map<String, Object> payload, String[] topicNames) {
        
        List<REST_Field_Mapping__mdt> fieldMappings = [
            SELECT SF_Field_Name__c, Request_Attribute__c, SF_Object_Name__c 
            FROM REST_Field_Mapping__mdt 
            WHERE Topic__c IN :topicNames
        ];
        
        List<Map<String, Object>> customerPayloads = new List<Map<String, Object>>();
        
        if (payload.containsKey('customers')) {
            for (Object customerObj : (List<Object>) payload.get('customers')) {
                customerPayloads.add((Map<String, Object>) customerObj);
            }
        } else if (payload.containsKey('customer')) {
            customerPayloads.add((Map<String, Object>) payload.get('customer'));
        }
        
        if (customerPayloads.isEmpty()) {
            return;
        }
        
        Set<String> shopIds = new Set<String>();
        Set<String> emails = new Set<String>();
        
        for (Map<String, Object> cust : customerPayloads) {
            if (cust.containsKey('id') && cust.get('id') != null) {
                shopIds.add(String.valueOf(cust.get('id')));
            } else if (cust.containsKey('customer_id') && cust.get('customer_id') != null) {
                shopIds.add(String.valueOf(cust.get('customer_id')));
            }
            
            if (cust.containsKey('email') && cust.get('email') != null) {
                emails.add(String.valueOf(cust.get('email')).trim().toLowerCase());
            } else if (cust.containsKey('email_address') && cust.get('email_address') != null) {
                emails.add(String.valueOf(cust.get('email_address')).trim().toLowerCase());
            }
        }
        
        Map<String, Account> existingByShopId = new Map<String, Account>();
        if (!shopIds.isEmpty()) {
            for (Account a : [
                SELECT Id, Shop_ID__c, PersonEmail
                FROM Account
                WHERE Shop_ID__c IN :shopIds
            ]) {
                existingByShopId.put(a.Shop_ID__c, a);
            }
        }
        
        Map<String, Account> existingByEmail = new Map<String, Account>();
        if (!emails.isEmpty()) {
            for (Account a : [
                SELECT Id, Shop_ID__c, PersonEmail
                FROM Account
                WHERE IsPersonAccount = true
                AND PersonEmail IN :emails
            ]) {
                if (a.PersonEmail != null) {
                    existingByEmail.put(a.PersonEmail.trim().toLowerCase(), a);
                }
            }
        }
        
        Map<Id, Account> accountsToUpdateById = new Map<Id, Account>();
        Map<String, Account> accountsToUpsertByShopId = new Map<String, Account>();
        
        for (Map<String, Object> customerMap : customerPayloads) {
            Account acc = (Account) processSingleCustomer(
                customerMap,
                fieldMappings,
                personAccountRecordTypeId,
                existingByShopId,
                existingByEmail
            );
            
            if (acc.Id != null) {
                accountsToUpdateById.put(acc.Id, acc);
            } else if (!String.isBlank(acc.Shop_ID__c)) {
                accountsToUpsertByShopId.put(acc.Shop_ID__c, acc);
            }
        }
        
        List<Id> accountIdsForLocaleSync = new List<Id>();
        
        if (!accountsToUpdateById.isEmpty()) {
            update accountsToUpdateById.values();
            
            for (Account acc : accountsToUpdateById.values()) {
                if (acc.Id != null && !String.isBlank(acc.Shop_ID__c)) {
                    accountIdsForLocaleSync.add(acc.Id);
                }
            }
        }
        
        if (!accountsToUpsertByShopId.isEmpty()) {
            upsert accountsToUpsertByShopId.values() Shop_ID__c;
            
            for (Account acc : accountsToUpsertByShopId.values()) {
                if (acc.Id != null && !String.isBlank(acc.Shop_ID__c)) {
                    accountIdsForLocaleSync.add(acc.Id);
                }
            }
        }
        
        if (!accountIdsForLocaleSync.isEmpty()) {
            ShopifyCustomerGraphQLService.syncCustomerLocalesAsync(accountIdsForLocaleSync);
        }
    }
    
    public static sObject processSingleCustomer(
        Map<String, Object> payload,
        List<REST_Field_Mapping__mdt> fieldMappings,
        Id personAccountRecordTypeId,
        Map<String, Account> existingByShopId,
        Map<String, Account> existingByEmail
    ) {
        Account newRecord = (Account) Utilities.doGenericMapping(
            'Account',
            payload,
            fieldMappings
        );
        
        newRecord.RecordTypeId = personAccountRecordTypeId;
        newRecord.Updated_by_Integration__c = true;
        
        String firstName = payload.get('first_name') == null
            ? null
            : String.valueOf(payload.get('first_name')).trim();
        
        String lastName = payload.get('last_name') == null
            ? null
            : String.valueOf(payload.get('last_name')).trim();
        
        if (!String.isBlank(lastName)) {
            // Both first and last name can remain as provided.
            newRecord.LastName = lastName;
            
            if (!String.isBlank(firstName)) {
                newRecord.FirstName = firstName;
            }
        } else if (!String.isBlank(firstName)) {
            // Salesforce Person Account requires LastName.
            // If Shopify provides only a first name, use it as LastName.
            newRecord.LastName = firstName;
            newRecord.FirstName = null;
        } else {
            // Final fallback when Shopify provides neither name.
            newRecord.LastName = 'Unknown';
        }
        
        doNuancedMapping(newRecord, payload);
        
        String shopId = null;
        
        if (payload.containsKey('id') && payload.get('id') != null) {
            shopId = String.valueOf(payload.get('id'));
            newRecord.Shop_ID__c = shopId;
        } else if (payload.containsKey('customer_id') && payload.get('customer_id') != null) {
            shopId = String.valueOf(payload.get('customer_id'));
            newRecord.Shop_ID__c = shopId;
        }
        
        String email = null;
        
        if (payload.containsKey('email') && payload.get('email') != null) {
            email = String.valueOf(payload.get('email')).trim().toLowerCase();
        } else if (payload.containsKey('email_address') && payload.get('email_address') != null) {
            email = String.valueOf(payload.get('email_address')).trim().toLowerCase();
        }
        
        // 1. Match by Shopify Id first
        if (!String.isBlank(shopId) && existingByShopId.containsKey(shopId)) {
            newRecord.Id = existingByShopId.get(shopId).Id;
            return newRecord;
        }
        
        // 2. Then match by Person Email
        if (!String.isBlank(email) && existingByEmail.containsKey(email)) {
            Account existing = existingByEmail.get(email);
            newRecord.Id = existing.Id;
            
            if (String.isBlank(newRecord.Shop_ID__c) && !String.isBlank(existing.Shop_ID__c)) {
                newRecord.Shop_ID__c = existing.Shop_ID__c;
            }
            
            return newRecord;
        }
        
        return newRecord;
    }
    
    public static Account processDefaultCustomer() {
        if (defaultCustomerAccount != null) {
            return defaultCustomerAccount;
        }
        
        List<Account> existingAccounts = [
            SELECT Id,
            Name,
            Shop_ID__c,
            RecordTypeId
            FROM Account
            WHERE Shop_ID__c = '1010101'
            LIMIT 1
        ];
        
        if (!existingAccounts.isEmpty()) {
            defaultCustomerAccount = existingAccounts[0];
            return defaultCustomerAccount;
        }
        
        Account personAccount = new Account();
        personAccount.RecordTypeId = personAccountRecordTypeId;
        personAccount.LastName = 'Default Customer';
        personAccount.Shop_ID__c = '1010101';
        personAccount.ShippingStreet = '71 - 75 Shelton Street';
        personAccount.ShippingCity = 'Camden';
        personAccount.ShippingState = 'London';
        personAccount.ShippingPostalCode = 'WC2H 9JQ';
        personAccount.ShippingCountry = 'UK';
        
        insert personAccount;
        
        defaultCustomerAccount = personAccount;
        return defaultCustomerAccount;
    }
    
    public static void doNuancedMapping(SObject newRecord, Map<String, Object> payload) {
        if (payload.containsKey('addresses')) {
            List<Object> addresses = (List<Object>) payload.get('addresses');
            for (Object thisAddressObject : addresses) {
                Map<String, Object> thisAddress = (Map<String, Object>) thisAddressObject;
                if (thisAddress != null) {
                    String addressLine1 = (String) thisAddress.get('address1');
                    String addressLine2 = (String) thisAddress.get('address2');
                    String fullAddress = ((addressLine1 != null ? addressLine1 : '') + 
                                          (addressLine2 != null ? ' ' + addressLine2 : '')).trim();
                    
                    if (thisAddress.containsKey('default') && (Boolean) thisAddress.get('default')) {
                        newRecord.put('ShippingStreet', fullAddress);
                        newRecord.put('ShippingCity', thisAddress.get('city'));
                        newRecord.put('ShippingState', thisAddress.get('province'));
                        newRecord.put('ShippingPostalCode', thisAddress.get('zip'));
                        newRecord.put('ShippingCountry', thisAddress.get('country'));
                    } else {
                        newRecord.put('BillingStreet', fullAddress);
                        newRecord.put('BillingCity', thisAddress.get('city'));
                        newRecord.put('BillingState', thisAddress.get('province'));
                        newRecord.put('BillingPostalCode', thisAddress.get('zip'));
                        newRecord.put('BillingCountry', thisAddress.get('country'));
                    }
                }
            }
        }
        
        // ─────────────────────────────────────────────────────────────────────────
        // Shopify marketing consent
        // ─────────────────────────────────────────────────────────────────────────
        
        Datetime latestConsentDateTime;
        Boolean hasConsentUpdate = false;
        
        // Email marketing consent
        if (
            payload.containsKey('email_marketing_consent') &&
            payload.get('email_marketing_consent') != null
        ) {
            Map<String, Object> emailConsent =
                (Map<String, Object>) payload.get('email_marketing_consent');
            
            if (
                emailConsent.containsKey('state') &&
                emailConsent.get('state') != null
            ) {
                String emailConsentState =
                    String.valueOf(emailConsent.get('state')).trim().toLowerCase();
                
                newRecord.put(
                    'Email_Opt_In__pc',
                    emailConsentState == 'subscribed'
                );
                
                hasConsentUpdate = true;
            }
            
            if (
                emailConsent.containsKey('consent_updated_at') &&
                emailConsent.get('consent_updated_at') != null
            ) {
                Datetime emailConsentDateTime =
                    parseShopifyConsentDateTime(
                        String.valueOf(emailConsent.get('consent_updated_at'))
                    );
                
                if (
                    emailConsentDateTime != null &&
                    (
                        latestConsentDateTime == null ||
                        emailConsentDateTime > latestConsentDateTime
                    )
                ) {
                    latestConsentDateTime = emailConsentDateTime;
                }
            }
        }
        
        
        // SMS marketing consent
        if (
            payload.containsKey('sms_marketing_consent') &&
            payload.get('sms_marketing_consent') != null
        ) {
            Map<String, Object> smsConsent =
                (Map<String, Object>) payload.get('sms_marketing_consent');
            
            if (
                smsConsent.containsKey('state') &&
                smsConsent.get('state') != null
            ) {
                String smsConsentState =
                    String.valueOf(smsConsent.get('state')).trim().toLowerCase();
                
                newRecord.put(
                    'SMS_Opt_In__pc',
                    smsConsentState == 'subscribed'
                );
                
                hasConsentUpdate = true;
            }
            
            if (
                smsConsent.containsKey('consent_updated_at') &&
                smsConsent.get('consent_updated_at') != null
            ) {
                Datetime smsConsentDateTime =
                    parseShopifyConsentDateTime(
                        String.valueOf(smsConsent.get('consent_updated_at'))
                    );
                
                if (
                    smsConsentDateTime != null &&
                    (
                        latestConsentDateTime == null ||
                        smsConsentDateTime > latestConsentDateTime
                    )
                ) {
                    latestConsentDateTime = smsConsentDateTime;
                }
            }
        }
        
        
        // WhatsApp marketing consent
        if (
            payload.containsKey('whats_app_marketing_consent') &&
            payload.get('whats_app_marketing_consent') != null
        ) {
            Map<String, Object> whatsappConsent =
                (Map<String, Object>) payload.get('whats_app_marketing_consent');
            
            if (
                whatsappConsent.containsKey('state') &&
                whatsappConsent.get('state') != null
            ) {
                String whatsappConsentState =
                    String.valueOf(whatsappConsent.get('state')).trim().toLowerCase();
                
                newRecord.put(
                    'Whatsapp_opt_in__pc',
                    whatsappConsentState == 'subscribed'
                );
                
                hasConsentUpdate = true;
            }
            
            if (
                whatsappConsent.containsKey('consent_updated_at') &&
                whatsappConsent.get('consent_updated_at') != null
            ) {
                Datetime whatsappConsentDateTime =
                    parseShopifyConsentDateTime(
                        String.valueOf(whatsappConsent.get('consent_updated_at'))
                    );
                
                if (
                    whatsappConsentDateTime != null &&
                    (
                        latestConsentDateTime == null ||
                        whatsappConsentDateTime > latestConsentDateTime
                    )
                ) {
                    latestConsentDateTime = whatsappConsentDateTime;
                }
            }
        }
        
        
        // Common consent metadata
        if (hasConsentUpdate) {
            if (latestConsentDateTime != null) {
                newRecord.put(
                    'Consent_Date_Time__c',
                    latestConsentDateTime
                );
            }
            
            newRecord.put(
                'Consent_Source__c',
                'Shopify'
            );
        }
        
        System.debug(
            LoggingLevel.INFO,
            'Shopify language values => locale=' + payload.get('locale') +
            ', customer_locale=' + payload.get('customer_locale') +
            ', language=' + payload.get('language')
        );
        
        
        // Language / Locale
        String shopifyLanguage = null;
        
        if (payload.containsKey('locale') && payload.get('locale') != null) {
            shopifyLanguage = String.valueOf(payload.get('locale')).trim();
        } else if (payload.containsKey('customer_locale') && payload.get('customer_locale') != null) {
            shopifyLanguage = String.valueOf(payload.get('customer_locale')).trim();
        } else if (payload.containsKey('language') && payload.get('language') != null) {
            shopifyLanguage = String.valueOf(payload.get('language')).trim();
        }
        
        if (!String.isBlank(shopifyLanguage)) {
            String normalizedLanguage = shopifyLanguage.toLowerCase();
            
            if (normalizedLanguage.startsWith('en')) {
                newRecord.put('Language__pc', 'English');
            } else if (normalizedLanguage.startsWith('fr')) {
                newRecord.put('Language__pc', 'French');
            } else if (normalizedLanguage.startsWith('de')) {
                newRecord.put('Language__pc', 'German');
            } else if (normalizedLanguage.startsWith('es')) {
                newRecord.put('Language__pc', 'Spanish');
            } else {
                newRecord.put('Language__pc', shopifyLanguage);
            }  
        }
    }
    
    private static Datetime parseShopifyConsentDateTime(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        
        try {
            String normalized = value.trim();
            
            Integer tIndex = normalized.indexOf('T');
            
            if (tIndex <= 0) {
                return null;
            }
            
            String datePart = normalized.substring(0, tIndex);
            String timeAndZonePart = normalized.substring(tIndex + 1);
            
            Integer offsetIndex = timeAndZonePart.indexOf('+');
            
            if (offsetIndex == -1) {
                offsetIndex = timeAndZonePart.indexOf('-');
            }
            
            Integer offsetMinutes = 0;
            String timePart = timeAndZonePart;
            
            if (offsetIndex > 0) {
                timePart = timeAndZonePart.substring(0, offsetIndex);
                
                String offsetPart =
                    timeAndZonePart.substring(offsetIndex);
                
                Integer offsetSign =
                    offsetPart.startsWith('-') ? -1 : 1;
                
                Integer offsetHours =
                    Integer.valueOf(offsetPart.substring(1, 3));
                
                Integer offsetMins =
                    Integer.valueOf(offsetPart.substring(4, 6));
                
                offsetMinutes =
                    offsetSign * ((offsetHours * 60) + offsetMins);
            } else if (timePart.endsWith('Z')) {
                timePart = timePart.substring(
                    0,
                    timePart.length() - 1
                );
            }
            
            if (timePart.contains('.')) {
                timePart = timePart.substringBefore('.');
            }
            
            List<String> dateParts = datePart.split('-');
            List<String> timeParts = timePart.split(':');
            
            if (dateParts.size() != 3 || timeParts.size() < 2) {
                return null;
            }
            
            Integer year = Integer.valueOf(dateParts[0]);
            Integer month = Integer.valueOf(dateParts[1]);
            Integer day = Integer.valueOf(dateParts[2]);
            
            Integer hour = Integer.valueOf(timeParts[0]);
            Integer minute = Integer.valueOf(timeParts[1]);
            
            Integer second = 0;
            
            if (timeParts.size() > 2) {
                second = Integer.valueOf(timeParts[2]);
            }
            
            Datetime result = Datetime.newInstanceGmt(
                year,
                month,
                day,
                hour,
                minute,
                second
            );
            
            // Convert the supplied offset time to UTC/GMT.
            return result.addMinutes(-offsetMinutes);
            
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'Unable to parse Shopify consent_updated_at: ' +
                value +
                ', error=' +
                e.getMessage()
            );
            
            return null;
        }
    }
}