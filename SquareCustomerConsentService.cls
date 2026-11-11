public without sharing class SquareCustomerConsentService {

    private static final String PERSON_ACCOUNT_RECORD_TYPE_NAME = 'PersonAccount';

    // ─────────────────────────────────────────────────────────────────────────
    // Called from SquareCustomerQueueable (customer.created / customer.updated)
    // Makes its own callout to retrieve the customer if not found in the payload.
    // Safe to call here because no DML has happened yet in that flow.
    // ─────────────────────────────────────────────────────────────────────────
    public static Id upsertPersonAccountFromSquareCustomer(
        String customerId,
        String eventType,
        String rawPayload
    ) {
        if (String.isBlank(customerId)) {
            return null;
        }

        Map<String, Object> customer = extractCustomerFromWebhookPayload(rawPayload);

        if (customer == null) {
            // Safe callout: no DML has occurred in this transaction yet
            customer = SquareApiClient.retrieveCustomer(customerId);
        }

        if (customer == null) {
            logCustomerSyncError(
                customerId,
                eventType,
                rawPayload,
                new AuraHandledException('Square customer response was null.')
            );
            return null;
        }

        return upsertPersonAccountFromCustomerMap(
            customerId,
            eventType,
            customer
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FIX — NEW OVERLOAD: Called from SquarePaymentQueueable AFTER all callouts
    // are done and BEFORE any DML.
    //
    // The OLD signature was:
    //   createContactFromPaymentIfConsented(String paymentId, Map payment)
    //
    // That old version called upsertPersonAccountFromSquareCustomer() which
    // called SquareApiClient.retrieveCustomer() internally — a callout AFTER
    // DML had already happened in syncPaymentToOrder(). That caused:
    //   "You have uncommitted work pending. Please commit or rollback before calling out"
    //
    // The FIX: SquarePaymentQueueable now fetches the customer upfront (before
    // any DML), then passes the pre-fetched Map<String,Object> squareCustomer
    // here. This method does zero callouts — pure SOQL + DML only.
    // ─────────────────────────────────────────────────────────────────────────
    public static Id createContactFromPaymentIfConsented(
        String paymentId,
        Map<String, Object> payment,
        Map<String, Object> squareCustomer   // pre-fetched — NO callout made here
    ) {
        if (String.isBlank(paymentId) || payment == null) {
            return null;
        }

        String customerId = (String) payment.get('customer_id');

        if (String.isBlank(customerId)) {
            return null;
        }

        // If caller could not fetch customer (e.g. Square returned null), skip
        if (squareCustomer == null) {
            System.debug(LoggingLevel.WARN,
                'SquareCustomerConsentService: squareCustomer was null for ' +
                'customerId=' + customerId + ', paymentId=' + paymentId +
                '. Skipping contact upsert.');
            return null;
        }

        // Pure DML path — no callout
        return upsertPersonAccountFromCustomerMap(
            customerId,
            'payment.created',
            squareCustomer
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // OLD 2-arg signature kept for backwards compatibility.
    // Only safe to call when no DML has already occurred in the transaction.
    // ─────────────────────────────────────────────────────────────────────────
    public static Id createContactFromPaymentIfConsented(
        String paymentId,
        Map<String, Object> payment
    ) {
        if (String.isBlank(paymentId) || payment == null) {
            return null;
        }

        String customerId = (String) payment.get('customer_id');

        if (String.isBlank(customerId)) {
            return null;
        }

        return upsertPersonAccountFromSquareCustomer(
            customerId,
            'payment.created',
            JSON.serialize(payment)
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core upsert logic — shared by all entry points.
    // NO callouts. Pure SOQL + DML.
    // ─────────────────────────────────────────────────────────────────────────
    private static Id upsertPersonAccountFromCustomerMap(
        String customerId,
        String eventType,
        Map<String, Object> customer
    ) {
        String email     = (String) customer.get('email_address');
        String firstName = (String) customer.get('given_name');
        String lastName  = (String) customer.get('family_name');
        String phone     = (String) customer.get('phone_number');
        String createdAt = (String) customer.get('created_at');
        String updatedAt = (String) customer.get('updated_at');

        if (String.isBlank(email) && String.isBlank(phone)) {
            System.debug(LoggingLevel.INFO,
                'Square customer skipped: missing both email and phone. customerId=' +
                customerId);
            return null;
        }

        if (String.isBlank(firstName) && String.isBlank(lastName)) {
            System.debug(LoggingLevel.INFO,
                'Square customer skipped: missing name. customerId=' + customerId);
            return null;
        }
        
        String resolvedFirstName = firstName;
        String resolvedLastName  = lastName;
        
        // Salesforce Person Account requires LastName.
        // If Square provides only first name, use it as Salesforce LastName.
        if (String.isBlank(lastName)) {
            resolvedLastName = firstName;
            resolvedFirstName = null;
        }
        
        Boolean emailMarketingOptIn = getEmailMarketingOptIn(customer);
        //Boolean smsMarketingOptIn   = false;

        Datetime consentDateTime = parseSquareDateTime(
            eventType == 'customer.created' ? createdAt : updatedAt
        );

        Id personAccountRecordTypeId = getPersonAccountRecordTypeId();

        Account existingAccount = findExistingPersonAccount(customerId, email, phone);

        if (existingAccount == null) {
            Account pa          = new Account();
            pa.RecordTypeId     = personAccountRecordTypeId;
            pa.FirstName = resolvedFirstName;
            pa.LastName  = resolvedLastName;

            if (!String.isBlank(email)) {
                pa.PersonEmail = email;
            }
            if (!String.isBlank(phone)) {
                pa.PersonMobilePhone = phone;
            }
            
            pa.Square_Customer_Id__c = customerId;
            // Square provides email consent through preferences.email_unsubscribed.
            // Square does not provide SMS or WhatsApp consent in the tested payload.
            pa.Email_Opt_In__pc = emailMarketingOptIn;   
            pa.Consent_Date_Time__c = consentDateTime;
            pa.Consent_Source__c = 'Square';
            
            Database.SaveResult insertResult = Database.insert(pa, false);

            if (!insertResult.isSuccess()) {
                for (Database.Error err : insertResult.getErrors()) {
                    System.debug(LoggingLevel.ERROR,
                        'SquareCustomerConsentService: Person Account insert failed. ' +
                        'customerId=' + customerId +
                        ', error=' + err.getMessage());
                }
                return null;
            }

            System.debug(LoggingLevel.INFO,
                'Square Person Account created: ' + pa.Id +
                ', customerId=' + customerId);

            return pa.Id;
        }
        
        // ── Update existing account ────────────────────────────────────────
        if (String.isBlank(existingAccount.Square_Customer_Id__c)) {
            existingAccount.Square_Customer_Id__c = customerId;
        }
        
        if (
            String.isBlank(existingAccount.FirstName) &&
            !String.isBlank(resolvedFirstName)
        ) {
            existingAccount.FirstName = resolvedFirstName;
        }
        
        if (
            (
                String.isBlank(existingAccount.LastName) ||
                existingAccount.LastName.equalsIgnoreCase('Unknown')
            ) &&
            !String.isBlank(resolvedLastName)
        ) {
            existingAccount.LastName = resolvedLastName;
        }
        
        if (
            !String.isBlank(resolvedLastName) &&
            (
                String.isBlank(existingAccount.LastName) ||
                existingAccount.LastName.equalsIgnoreCase('Unknown')
            )
        ) {
            existingAccount.LastName = resolvedLastName;
        }

        if (String.isBlank(existingAccount.PersonEmail) && !String.isBlank(email)) {
            existingAccount.PersonEmail = email;
        }

        if (String.isBlank(existingAccount.PersonMobilePhone) && !String.isBlank(phone)) {
            existingAccount.PersonMobilePhone = phone;
        }
        
        // Update only the consent channel that Square actually provides.
        // Do not overwrite existing consent when Square does not provide it.
        if (emailMarketingOptIn != null) {
            existingAccount.Email_Opt_In__pc = emailMarketingOptIn;
            existingAccount.Consent_Date_Time__c = consentDateTime;
            existingAccount.Consent_Source__c = 'Square';
        }
        
        List<Database.SaveResult> updateResults =
            Database.update(new List<Account>{ existingAccount }, false);

        for (Database.SaveResult sr : updateResults) {
            if (sr.isSuccess()) {
                System.debug(LoggingLevel.INFO,
                    'Square Person Account updated: ' + existingAccount.Id +
                    ', customerId=' + customerId);
            } else {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(LoggingLevel.ERROR,
                        'SquareCustomerConsentService: Person Account update failed. ' +
                        'accountId=' + existingAccount.Id +
                        ', customerId=' + customerId +
                        ', error=' + err.getMessage());
                }
            }
        }

        return existingAccount.Id;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static Boolean getEmailMarketingOptIn(Map<String, Object> customer) {
        Map<String, Object> preferences =
            (Map<String, Object>) customer.get('preferences');

        if (
            preferences != null &&
            preferences.containsKey('email_unsubscribed') &&
            preferences.get('email_unsubscribed') != null
        ) {
            Boolean emailUnsubscribed = (Boolean) preferences.get('email_unsubscribed');
            return !emailUnsubscribed;
        }
        
        // null means Square did not provide an email consent value.
        // The caller must preserve the existing Salesforce value.
        return null;    }
    
    private static Account findExistingPersonAccount(
        String customerId,
        String email,
        String phone
    ) {
        if (!String.isBlank(customerId)) {
            List<Account> accounts = [
                SELECT Id, FirstName, LastName, PersonEmail, PersonMobilePhone,
                Square_Customer_Id__c,
                Email_Opt_In__pc,
                SMS_Opt_In__pc,
                WhatsApp_Opt_In__pc,
                Consent_Date_Time__c,
                Consent_Source__c
                FROM Account
                WHERE IsPersonAccount = true
                AND Square_Customer_Id__c = :customerId
                LIMIT 1
            ];
            if (!accounts.isEmpty()) return accounts[0];
        }
        
        if (!String.isBlank(email)) {
            List<Account> accounts = [
                SELECT Id, FirstName, LastName, PersonEmail, PersonMobilePhone,
                Square_Customer_Id__c,
                Email_Opt_In__pc,
                SMS_Opt_In__pc,
                WhatsApp_Opt_In__pc,
                Consent_Date_Time__c,
                Consent_Source__c
                FROM Account
                WHERE IsPersonAccount = true
                AND PersonEmail = :email
                LIMIT 1
            ];
            if (!accounts.isEmpty()) return accounts[0];
        }
        
        if (!String.isBlank(phone)) {
            List<Account> accounts = [
                SELECT Id, FirstName, LastName, PersonEmail, PersonMobilePhone,
                Square_Customer_Id__c,
                Email_Opt_In__pc,
                SMS_Opt_In__pc,
                WhatsApp_Opt_In__pc,
                Consent_Date_Time__c,
                Consent_Source__c                FROM Account
                WHERE IsPersonAccount = true
                AND PersonMobilePhone = :phone
                LIMIT 1
            ];
            if (!accounts.isEmpty()) return accounts[0];
        }
        
        return null;
    }

    private static Id getPersonAccountRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];

        if (rts.isEmpty()) {
            throw new AuraHandledException('No Person Account record type found.');
        }

        return rts[0].Id;
    }

    private static Datetime parseSquareDateTime(String value) {
        if (String.isBlank(value)) return System.now();
        try {
            String normalized = value.replace('T', ' ').replace('Z', '');
            if (normalized.contains('.')) {
                normalized = normalized.substringBefore('.');
            }
            return Datetime.valueOfGmt(normalized);
        } catch (Exception e) {
            return System.now();
        }
    }

    private static Map<String, Object> extractCustomerFromWebhookPayload(
        String rawPayload
    ) {
        if (String.isBlank(rawPayload)) return null;

        try {
            Map<String, Object> payload =
                (Map<String, Object>) JSON.deserializeUntyped(rawPayload);

            Map<String, Object> dataMap =
                (Map<String, Object>) payload.get('data');
            if (dataMap == null) return null;

            Map<String, Object> objectMap =
                (Map<String, Object>) dataMap.get('object');
            if (objectMap == null) return null;

            return (Map<String, Object>) objectMap.get('customer');

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Could not parse Square customer from webhook payload: ' +
                e.getMessage());
            return null;
        }
    }

    public static void logCustomerSyncError(
        String customerId,
        String eventType,
        String rawPayload,
        Exception e
    ) {
        System.debug(LoggingLevel.ERROR,
            'Square customer sync error. customerId=' + customerId +
            ', eventType=' + eventType +
            ', error=' + e.getMessage() +
            ', payload=' + rawPayload);
    }
}