public without sharing class SquareOrderSyncService {
    
    private static final String SQUARE_PRICEBOOK_NAME = 'Square Pricebook';
    
    /**
* Called from SquarePaymentQueueable AFTER all callouts are done.
* payment and squareOrder are pre-fetched — no callouts happen here.
*/
    public static void syncPaymentToOrder(
        String paymentId,
        Map<String, Object> payment,
        Map<String, Object> squareOrder
    ) {
        if (payment == null) return;
        
        // Existing validation preserved.
        if (String.isBlank(paymentId) || paymentId.length() < 20) {
            System.debug(
                LoggingLevel.ERROR,
                'syncPaymentToOrder: Invalid Square payment ID: ' + paymentId
            );
            return;
        }
        
        String squarePaymentId  = (String) payment.get('id');
        String squareOrderId    = (String) payment.get('order_id');
        String teamMemberId     = (String) payment.get('team_member_id');
        String locationId       = (String) payment.get('location_id');
        String receiptUrl       = (String) payment.get('receipt_url');
        String squareCustomerId = (String) payment.get('customer_id');
        
        /*String terminalNote = payment.get('note') == null
            ? null
            : String.valueOf(payment.get('note'));*/
        
        if (String.isBlank(squareCustomerId) && squareOrder != null) {
            squareCustomerId = extractCustomerIdFromSquareOrder(squareOrder);
        }
        
        Id salesAssistantUserId = findSalesAssistantUserBySquareId(teamMemberId);
        
        if (salesAssistantUserId == null && !String.isBlank(teamMemberId)) {
            System.enqueueJob(
                new SquareSalesAssistantOrderQueueable(
                    'CREATE_USER',
                    teamMemberId,
                    paymentId,
                    JSON.serialize(payment),
                    squareOrder == null ? null : JSON.serialize(squareOrder)
                )
            );
            
            System.debug(
                LoggingLevel.INFO,
                'SquareOrderSyncService: Sales Assistant User not found. ' +
                'Queued User creation and deferred Order sync. teamMemberId=' +
                teamMemberId +
                ', paymentId=' +
                paymentId
            );
            
            return;
        }
        
        /*if (salesAssistantUserId == null && !String.isBlank(teamMemberId)) {
System.enqueueJob(
new SquareSalesAssistantUserCreateQueueable(
teamMemberId,
JSON.serialize(payment),
squareOrder == null ? null : JSON.serialize(squareOrder),
paymentId
)
);

System.debug(
LoggingLevel.INFO,
'SquareOrderSyncService: Sales Assistant User not found. ' +
'Queued User creation and deferred Order sync. teamMemberId=' + teamMemberId +
', paymentId=' + paymentId
);

return;
}*/
        
        Id matchedAccountId = findPersonAccountIdBySquareCustomerId(squareCustomerId);
        
        if (matchedAccountId == null) {
            System.debug(
                LoggingLevel.WARN,
                'SquareOrderSyncService: no matching Person Account found for Square customer_id=' +
                squareCustomerId +
                '. Skipping order creation.'
            );
            return;
        }
        
        List<Schema.Location> locs = [
            SELECT Id
            FROM Location
            WHERE Name = 'Shop Location'
            LIMIT 1
        ];
        
        /*
* CHANGE:
* POS Orders should use Square Pricebook.
* If Square Pricebook is missing/inactive, the Order is still created/updated,
* but Order Products are skipped safely.
*/
        Id squarePricebookId = getSquarePricebookId();
        
        /*
* CHANGE:
* Query current refund fields and Pricebook2Id so a later payment.updated event
* does not overwrite Refunded/Restocked back to Paid.
*/
        List<Order> existingOrders = [
            SELECT Id,
            Pricebook2Id,
            Financial_Status__c,
            Fulfillment_Status__c
            FROM Order
            WHERE Square_Payment_Id__c = :squarePaymentId
            LIMIT 1
        ];
        
        Order ord;
        Boolean isExistingOrder = false;
        
        if (!existingOrders.isEmpty()) {
            ord = existingOrders[0];
            isExistingOrder = true;
        } else {
            ord = new Order();
            ord.AccountId = matchedAccountId;
        }
        
        //Record Type Assignment
        ord.RecordTypeId =
            Schema.SObjectType.Order.getRecordTypeInfosByName()
            .get('Pop-up')
            .getRecordTypeId();
        
        ord.Square_Payment_Id__c  = squarePaymentId;
        ord.Square_Order_Id__c    = squareOrderId;
        ord.Square_Location_Id__c = locationId;
        ord.Square_Receipt_Url__c = receiptUrl;
        ord.Square_Raw_JSON__c    = JSON.serialize(payment);

/*
 * Pop-up Provider matching
 *
 * Accounts are manually created in Salesforce.
 * No Account is created by the integration.
 */
List<Account> popUpProviderAccounts = new List<Account>();

if (!String.isBlank(locationId)) {
    popUpProviderAccounts = [
        SELECT Id
        FROM Account
        WHERE Square_Location_Id__c = :locationId
        AND RecordType.Name = 'Pop-up Provider'
        LIMIT 2
    ];
}

if (popUpProviderAccounts.size() == 1) {

    ord.Type = 'POS';
    ord.Pop_up_Provider__c = popUpProviderAccounts[0].Id;

    System.debug(
        LoggingLevel.INFO,
        'SquareOrderSyncService: Pop-up Provider matched. ' +
        'squareOrderId=' + squareOrderId +
        ', squareLocationId=' + locationId +
        ', accountId=' + popUpProviderAccounts[0].Id
    );

} else {

    ord.Type = 'POS';

    if (popUpProviderAccounts.size() > 1) {
        System.debug(
            LoggingLevel.ERROR,
            'SquareOrderSyncService: Multiple Pop-up Provider Accounts found. ' +
            'squareLocationId=' + locationId
        );
    }
}

ord.Status = 'Draft';
ord.EffectiveDate = Date.today();
        
        /*
* CHANGE:
* Assign Square Pricebook to POS Order.
* For new Orders, this is required before creating Order Products.
* For existing Orders, set only if Pricebook2Id is blank to avoid changing
* pricebook on an Order that may already have OrderItems.
*/
        if (squarePricebookId != null && ord.Pricebook2Id == null) {
            ord.Pricebook2Id = squarePricebookId;
        }
        
        if (!locs.isEmpty()) {
            ord.Location__c = locs[0].Id;
        }
        
        if (salesAssistantUserId != null) {
            ord.Sales_Assistant__c = salesAssistantUserId;
        }
        
        Map<String, Object> amountMoney =
            (Map<String, Object>) payment.get('amount_money');
        
        if (amountMoney != null && amountMoney.get('amount') != null) {
            ord.Shop_Total_Amount__c =
                Decimal.valueOf(String.valueOf(amountMoney.get('amount'))) / 100;
        }
        
        /*
* CHANGE:
* Prevent refund overwrite.
*
* Old behavior always set:
*   Financial_Status__c = Paid
*
* New behavior:
*   - If Square payment says fully refunded, mark Refunded / Restocked.
*   - If Salesforce already says Refunded, keep Refunded / Restocked.
*   - Otherwise keep existing behavior and mark Paid.
*/
        Boolean paymentIsFullyRefunded = isPaymentFullyRefunded(payment);
        
        if (paymentIsFullyRefunded) {
            ord.Financial_Status__c = 'Refunded';
            ord.Fulfillment_Status__c = 'Restocked';
            
            System.debug(
                LoggingLevel.INFO,
                'SquareOrderSyncService: payment is fully refunded. ' +
                'Keeping Order refunded/restocked. paymentId=' + squarePaymentId
            );
            
        } else if (
            isExistingOrder &&
            ord.Financial_Status__c == 'Refunded'
        ) {
            ord.Financial_Status__c = 'Refunded';
            ord.Fulfillment_Status__c = 'Restocked';
            
            System.debug(
                LoggingLevel.INFO,
                'SquareOrderSyncService: existing Order is already Refunded. ' +
                'Skipping overwrite back to Paid. orderId=' + ord.Id +
                ', paymentId=' + squarePaymentId
            );
            
        } else {
            /*
* Existing behavior preserved for normal non-refunded payments.
*/
            ord.Financial_Status__c = 'Paid';
        }
        
        if (ord.Id != null) {
            update ord;
            
        } else {
            ord.AccountId = matchedAccountId;
            
            try {
                insert ord;
                
            } catch (DmlException e) {
                if (e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                    recoverDuplicateOrder(
                        ord,
                        squarePaymentId,
                        squarePricebookId,
                        paymentIsFullyRefunded
                    );
                } else {
                    throw e;
                }
            }
        }
            
            /*
* CHANGE:
* Order Product creation moved to a helper so this service does not become too large.
* Existing Order creation/update process remains the same.
*
* Safe behavior:
* - If Square order has products and they match Salesforce products, create OrderItems.
* - If no match is found, skip OrderItems.
* - If Square Pricebook is missing, skip OrderItems.
* - Never block Order creation because of missing products.
*/
        if (ord.Id != null && squareOrder != null) {
            SquareOrderItemSyncService.syncOrderItems(
                ord.Id,
                squareOrder,
                squarePricebookId
            );
        }
    }
        
        @TestVisible
        private static void recoverDuplicateOrder(
            Order ord,
            String squarePaymentId,
            Id squarePricebookId,
            Boolean paymentIsFullyRefunded
        ) {
            System.debug(
                LoggingLevel.WARN,
                'SquareOrderSyncService: race condition detected for ' +
                squarePaymentId + ', fetching existing record to update.'
            );
            
            List<Order> raceOrders = [
                SELECT Id,
                Pricebook2Id,
                Financial_Status__c,
                Fulfillment_Status__c
                FROM Order
                WHERE Square_Payment_Id__c = :squarePaymentId
                LIMIT 1
            ];
            
            if (!raceOrders.isEmpty()) {
                Order existingRaceOrder = raceOrders[0];
                
                ord.Id = existingRaceOrder.Id;
                
                if (squarePricebookId != null && existingRaceOrder.Pricebook2Id == null) {
                    ord.Pricebook2Id = squarePricebookId;
                }
                
                if (
                    paymentIsFullyRefunded ||
                    existingRaceOrder.Financial_Status__c == 'Refunded'
                ) {
                    ord.Financial_Status__c = 'Refunded';
                    ord.Fulfillment_Status__c = 'Restocked';
                    
                    System.debug(
                        LoggingLevel.INFO,
                        'SquareOrderSyncService: duplicate recovery preserved refunded/restocked status. ' +
                        'orderId=' + ord.Id +
                        ', paymentId=' + squarePaymentId
                    );
                }
                
                update ord;
            }
        }
        
        @TestVisible
        private static Id getSquarePricebookId() {
            List<Pricebook2> pricebooks = [
                SELECT Id
                FROM Pricebook2
                WHERE Name = :SQUARE_PRICEBOOK_NAME
                AND IsActive = true
                LIMIT 1
            ];
            
            if (pricebooks.isEmpty()) {
                System.debug(
                    LoggingLevel.WARN,
                    'SquareOrderSyncService: active Square Pricebook not found. Name=' +
                    SQUARE_PRICEBOOK_NAME +
                    '. Order will still be created/updated, but OrderItems will be skipped.'
                );
                return null;
            }
            
            return pricebooks[0].Id;
        }
        
        /*
* CHANGE:
* No callout. Uses already-fetched Square payment map to detect full refund.
*/	
        @TestVisible
        private static Boolean isPaymentFullyRefunded(Map<String, Object> payment) {
            if (payment == null) {
                return false;
            }
            
            Decimal paymentAmount = extractMoneyAmount(payment, 'amount_money');
            Decimal refundedAmount = extractMoneyAmount(payment, 'refunded_money');
            
            System.debug(
                LoggingLevel.INFO,
                'SquareOrderSyncService: refund check from payment payload. ' +
                'paymentAmount=' + paymentAmount +
                ', refundedAmount=' + refundedAmount
            );
            
            return paymentAmount > 0 && refundedAmount >= paymentAmount;
        }
        
        @TestVisible
        private static Decimal extractMoneyAmount(
            Map<String, Object> root,
            String fieldName
        ) {
            if (root == null || String.isBlank(fieldName)) {
                return 0;
            }
            
            if (root.get(fieldName) == null) {
                return 0;
            }
            
            Map<String, Object> money =
                (Map<String, Object>) root.get(fieldName);
            
            if (money == null || money.get('amount') == null) {
                return 0;
            }
            
            return Decimal.valueOf(String.valueOf(money.get('amount')));
        }
        
        @TestVisible
        private static Id findSalesAssistantUserBySquareId(String teamMemberId) {
            if (String.isBlank(teamMemberId)) return null;
            
            List<User> users = [
                SELECT Id
                FROM User
                WHERE Square_Team_Member_Id__c = :teamMemberId
                LIMIT 1
            ];
            
            return users.isEmpty() ? null : users[0].Id;
        }
        
        @TestVisible
        private static String extractSalesAssistantName(
            Map<String, Object> payment
        ) {
            if (payment == null) {
                return null;
            }
            
            if (payment.get('team_member_name') != null) {
                return String.valueOf(payment.get('team_member_name'));
            }
            
            if (payment.get('employee_name') != null) {
                return String.valueOf(payment.get('employee_name'));
            }
            
            if (payment.get('creator_name') != null) {
                return String.valueOf(payment.get('creator_name'));
            }
            
            return null;
        }
        
        @TestVisible
        private static Profile getFreeUserProfile() {
            List<Profile> profiles = [
                SELECT Id, Name, UserLicense.Name
                FROM Profile
                WHERE UserLicense.Name IN ('Chatter Free', 'Identity')
                ORDER BY UserLicense.Name
                LIMIT 1
            ];
            
            if (profiles.isEmpty()) {
                throw new AuraHandledException(
                    'No free User profile found. Create or identify a Chatter Free/Identity profile first.'
                );
            }
            
            return profiles[0];
        }
        
        @TestVisible
        private static String buildUserAlias(
            String firstName,
            String lastName
        ) {
            String source = '';
            
            if (!String.isBlank(firstName)) {
                source += firstName.left(1);
            }
            
            if (!String.isBlank(lastName)) {
                source += lastName;
            }
            
            if (String.isBlank(source)) {
                source = 'sq_user';
            }
            
            source = source.replaceAll('[^A-Za-z0-9]', '').toLowerCase();
            
            if (source.length() > 8) {
                source = source.left(8);
            }
            
            return source;
        }
        
        public static Id getDefaultSquareCustomerAccountId() {
            List<Account> accounts = [
                SELECT Id
                FROM Account
                WHERE Name = 'Square POS Customer'
                LIMIT 1
            ];
            
            if (!accounts.isEmpty()) return accounts[0].Id;
            
            Account acc = new Account(Name = 'Square POS Customer');
            insert acc;
            
            return acc.Id;
        }
        
        @TestVisible
        private static String extractCustomerIdFromSquareOrder(
            Map<String, Object> squareOrder
        ) {
            if (squareOrder == null) return null;
            
            if (squareOrder.get('customer_id') != null) {
                return (String) squareOrder.get('customer_id');
            }
            
            Object tendersObj = squareOrder.get('tenders');
            
            if (tendersObj != null) {
                for (Object tenderObj : (List<Object>) tendersObj) {
                    Map<String, Object> tender =
                        (Map<String, Object>) tenderObj;
                    
                    if (
                        tender != null &&
                        tender.get('customer_id') != null
                    ) {
                        return (String) tender.get('customer_id');
                    }
                }
            }
            
            return null;
        }
        
        @TestVisible
        private static Id findPersonAccountIdBySquareCustomerId(
            String squareCustomerId
        ) {
            if (String.isBlank(squareCustomerId)) {
                return null;
            }
            
            List<Account> accounts = [
                SELECT Id
                FROM Account
                WHERE IsPersonAccount = true
                AND Square_Customer_Id__c = :squareCustomerId
                LIMIT 1
            ];
            
            return accounts.isEmpty() ? null : accounts[0].Id;
        }
    }