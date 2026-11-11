public without sharing class SquareOrderStatusSyncService {
    
    public static void syncSquareOrder(
        String squareOrderId,
        String eventType,
        String rawPayload
    ) {
        if (String.isBlank(squareOrderId)) {
            System.debug(
                LoggingLevel.WARN,
                'SquareOrderStatusSyncService: blank squareOrderId. Skipping.'
            );
            return;
        }
        
        // ─────────────────────────────────────────────────────────────────────
        // STEP 1 — ALL CALLOUTS FIRST
        // ─────────────────────────────────────────────────────────────────────
        
        Map<String, Object> squareOrder =
            SquareApiClient.retrieveSquareOrder(squareOrderId);
        
        if (squareOrder == null) {
            System.debug(
                LoggingLevel.WARN,
                'SquareOrderStatusSyncService: Square order not found. squareOrderId=' +
                squareOrderId
            );
            return;
        }
        
        // Square location_id is the sole key for the Pop-up Provider Customer lookup.
        // It is also stored on Order.Square_Location_Id__c for traceability.
        String locationId = (String) squareOrder.get('location_id');
        System.debug(
            LoggingLevel.INFO,
            'SquareOrderStatusSyncService: Square Location ID received. squareLocationId=' +
            locationId
        );

        Decimal totalAmount = extractTotalAmount(squareOrder);
        
        String financialStatus = mapFinancialStatus(squareOrder);
        String fulfillmentStatus = mapFulfillmentStatus(squareOrder, financialStatus);
        
        String squarePaymentId = extractPaymentIdFromSquareOrder(squareOrder);
        
        System.debug(
            LoggingLevel.INFO,
            'SquareOrderStatusSyncService: extracted squarePaymentId=' +
            squarePaymentId +
            ', squareOrderId=' +
            squareOrderId +
            ', eventType=' +
            eventType
        );
        
        Map<String, Object> payment = null;
        
        if (String.isNotBlank(squarePaymentId)) {
            try {
                payment = SquareApiClient.retrievePayment(squarePaymentId);
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.WARN,
                    'SquareOrderStatusSyncService: could not retrieve payment. ' +
                    'squarePaymentId=' +
                    squarePaymentId +
                    ', squareOrderId=' +
                    squareOrderId +
                    ', error=' +
                    e.getMessage()
                );
            }
        }
        
        String squareCustomerId = extractCustomerIdFromSquareOrder(squareOrder);
        
        if (
            String.isBlank(squareCustomerId) &&
            payment != null &&
            payment.get('customer_id') != null
        ) {
            squareCustomerId = String.valueOf(payment.get('customer_id'));
        }
        
        System.debug(
            LoggingLevel.INFO,
            'SquareOrderStatusSyncService: squareOrderId=' +
            squareOrderId +
            ', squareCustomerId=' +
            squareCustomerId +
            ', eventType=' +
            eventType
        );
        
        Boolean paymentIsFullyRefunded = false;
        
        if (payment != null) {
            Decimal paymentAmount = extractMoneyAmount(payment, 'amount_money');
            Decimal refundedAmount = extractMoneyAmount(payment, 'refunded_money');
            
            paymentIsFullyRefunded =
                paymentAmount > 0 &&
                refundedAmount >= paymentAmount;
            
            System.debug(
                LoggingLevel.INFO,
                'SquareOrderStatusSyncService: payment refund check from pre-fetched payment. ' +
                'squarePaymentId=' +
                squarePaymentId +
                ', paymentAmount=' +
                paymentAmount +
                ', refundedAmount=' +
                refundedAmount +
                ', paymentIsFullyRefunded=' +
                paymentIsFullyRefunded
            );
        }
        
        // ─────────────────────────────────────────────────────────────────────
        // IMPORTANT FIX:
        // For order.updated, do NOT create a new Salesforce Order.
        // Refunds can trigger Square order.updated events. If no existing Order
        // is found, inserting here creates duplicate Orders under Square POS Customer.
        // ─────────────────────────────────────────────────────────────────────
        
        Order ord = findExistingOrder(squarePaymentId, squareOrderId);
        
        Boolean isInsert = false;
        
        if (ord == null) {
            if (eventType == 'order.updated' || eventType == 'order.fulfillment.updated') {
                System.debug(
                    LoggingLevel.WARN,
                    'SquareOrderStatusSyncService: ' +
                    eventType +
                    ' received but no existing Salesforce Order found. ' +
                    'Skipping insert to prevent duplicate refund/order-update Order. ' +
                    'squareOrderId=' +
                    squareOrderId +
                    ', squarePaymentId=' +
                    squarePaymentId
                );
                return;
            }
            
            // ─────────────────────────────────────────────────────────────
            // IMPORTANT FIX:
            // Square generates empty, zero-value "COMPLETED" order shells as a
            // side effect of some refund/return flows on the device (order.created
            // fires with a distinct Square order ID, no line items, no tenders,
            // $0 total). These are not real sales. Without this guard, every one
            // of these shells becomes a phantom duplicate Order in Salesforce
            // (GBP 0.00, Draft, Fulfilled/Paid defaults) right when a refund is
            // processed. A genuine POS sale always has at least one line item
            // and a nonzero total by the time order.created reaches this
            // service (checkout completes items-in-hand, not incrementally),
            // so this guard does not affect legitimate new orders.
            // ─────────────────────────────────────────────────────────────
            if (!squareOrderHasLineItems(squareOrder) && totalAmount == 0) {
                System.debug(
                    LoggingLevel.WARN,
                    'SquareOrderStatusSyncService: skipping empty/zero-value Square order. ' +
                    'No line items and $0 total — likely a refund side-effect shell, not a ' +
                    'real sale. squareOrderId=' +
                    squareOrderId +
                    ', eventType=' +
                    eventType
                );
                return;
            }
            
            ord = new Order();
            isInsert = true;
            
            System.debug(
                LoggingLevel.INFO,
                'SquareOrderStatusSyncService: no existing Order found. Creating new Salesforce Order. ' +
                'squareOrderId=' +
                squareOrderId +
                ', squarePaymentId=' +
                squarePaymentId +
                ', eventType=' +
                eventType
            );
        }
        
        ord.RecordTypeId =
            Schema.SObjectType.Order.getRecordTypeInfosByName()
            .get('Pop-up')
            .getRecordTypeId();
        
        // ─────────────────────────────────────────────────────────────────────
        // STEP 2 — DML AFTER ALL CALLOUTS
        // Create/update Person Account before creating/updating the Order.
        // ─────────────────────────────────────────────────────────────────────
        
        Id resolvedAccountId;
        
        Map<String, Object> squareCustomer = null;
        
        if (String.isNotBlank(squareCustomerId)) {
            try {
                squareCustomer = SquareApiClient.retrieveCustomer(squareCustomerId);
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.WARN,
                    'SquareOrderStatusSyncService: could not retrieve Square customer. ' +
                    'squareCustomerId=' +
                    squareCustomerId +
                    ', squareOrderId=' +
                    squareOrderId +
                    ', error=' +
                    e.getMessage()
                );
            }
        }
        
        if (
            String.isNotBlank(squareCustomerId) &&
            squareCustomer != null
        ) {
            Map<String, Object> paymentForCustomerSync = payment;
            
            if (paymentForCustomerSync == null) {
                paymentForCustomerSync = new Map<String, Object>();
                paymentForCustomerSync.put('customer_id', squareCustomerId);
            }
            
            try {
                resolvedAccountId =
                    SquareCustomerConsentService.createContactFromPaymentIfConsented(
                        String.isNotBlank(squarePaymentId) ? squarePaymentId : squareOrderId,
                        paymentForCustomerSync,
                        squareCustomer
                    );
                
                System.debug(
                    LoggingLevel.INFO,
                    'SquareOrderStatusSyncService: Person Account synced before Order DML. ' +
                    'squareOrderId=' +
                    squareOrderId +
                    ', squareCustomerId=' +
                    squareCustomerId +
                    ', accountId=' +
                    resolvedAccountId
                );
                
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'SquareOrderStatusSyncService: Person Account sync failed. ' +
                    'squareOrderId=' +
                    squareOrderId +
                    ', squareCustomerId=' +
                    squareCustomerId +
                    ', error=' +
                    e.getMessage()
                );
            }
        }
        
        if (resolvedAccountId == null && String.isNotBlank(squareCustomerId)) {
            resolvedAccountId = findPersonAccountIdBySquareCustomerId(squareCustomerId);
        }
        
        /*
* If this is an existing Order and account resolution fails,
* keep the existing AccountId. Do not replace it with Square POS Customer.
*/
        if (resolvedAccountId == null && !isInsert && ord.AccountId != null) {
            resolvedAccountId = ord.AccountId;
            
            System.debug(
                LoggingLevel.INFO,
                'SquareOrderStatusSyncService: keeping existing Order AccountId. ' +
                'orderId=' +
                ord.Id +
                ', accountId=' +
                resolvedAccountId +
                ', squareOrderId=' +
                squareOrderId
            );
        }
        
        /*
* If Square sent a customer but we cannot create/find that Person Account,
* do not assign the default account. That creates the wrong behavior.
*/
        if (resolvedAccountId == null && String.isNotBlank(squareCustomerId)) {
            System.debug(
                LoggingLevel.ERROR,
                'SquareOrderStatusSyncService: Square customer exists but no Person Account could be created/found. ' +
                'Skipping Order creation/update to avoid assigning default account. ' +
                'squareOrderId=' +
                squareOrderId +
                ', squareCustomerId=' +
                squareCustomerId
            );
            return;
        }
        
        /*
* Only use default account for truly anonymous Square POS order.created events.
* Never use default account for order.updated/refund-related updates.
*/
        if (resolvedAccountId == null) {
            if (!isInsert) {
                System.debug(
                    LoggingLevel.WARN,
                    'SquareOrderStatusSyncService: no resolved account for existing Order update. ' +
                    'Keeping existing account and continuing. orderId=' +
                    ord.Id +
                    ', squareOrderId=' +
                    squareOrderId
                );
                resolvedAccountId = ord.AccountId;
            } else {
                resolvedAccountId = SquareOrderSyncService.getDefaultSquareCustomerAccountId();
                
                System.debug(
                    LoggingLevel.WARN,
                    'SquareOrderStatusSyncService: no Square customer found on order.created. ' +
                    'Using default Square POS Customer Account. squareOrderId=' +
                    squareOrderId +
                    ', defaultAccountId=' +
                    resolvedAccountId
                );
            }
        }
        
        // Resolve the Customer record referenced by Order.Pop_up_Provider__c
        // using the exact Square Location ID only. No record names are compared.
        Id popUpProviderCustomerId;
        if (String.isNotBlank(locationId)) {
            try {
                popUpProviderCustomerId =
                    SquarePopUpAccountService.getPopUpProviderCustomerId(locationId);
            } catch (Exception providerException) {
                System.debug(
                    LoggingLevel.ERROR,
                    'SquareOrderStatusSyncService: could not resolve Pop-up Provider Customer. ' +
                    'squareLocationId=' + locationId +
                    ', error=' + providerException.getMessage()
                );
            }
        }

        System.debug(
            LoggingLevel.INFO,
            'SquareOrderStatusSyncService: Pop-up Provider resolution completed using ' +
            'Square Location ID only. squareLocationId=' + locationId +
            ', providerCustomerId=' + popUpProviderCustomerId
        );

        Id squarePricebookId = getSquarePricebookId();
        
        // This is the Salesforce inventory Location, not the Square location.
        // InventoryRuleService resolves POS to Warehouse (metadata first, fallback second).
        Id inventoryLocationId = InventoryRuleService.getLocationIdForOrderType('POS');

        ord.AccountId = resolvedAccountId;
        ord.Square_Order_Id__c = squareOrderId;
        ord.Square_Location_Id__c = locationId;
        ord.Shop_Total_Amount__c = totalAmount;
        ord.Square_Raw_JSON__c = JSON.serialize(squareOrder);
        ord.Type = 'POS';

        if (inventoryLocationId != null) {
            ord.Location__c = inventoryLocationId;
        }

        // Pop_up_Provider__c is a Customer lookup, not a text field. Assign the
        // resolved provider Customer Id; never overwrite Location__c (Warehouse).
        applyPopUpProviderToOrder(ord, popUpProviderCustomerId);
        
        if (isInsert) {
            ord.Status = 'Draft';
            ord.EffectiveDate = Date.today();
        }
        
        if (String.isNotBlank(squarePaymentId) && squarePaymentId != squareOrderId) {
            ord.Square_Payment_Id__c = squarePaymentId;
        }
        
        if (squarePricebookId != null && ord.Pricebook2Id == null) {
            ord.Pricebook2Id = squarePricebookId;
        }
        
        if (paymentIsFullyRefunded) {
            ord.Financial_Status__c = 'Refunded';
            ord.Fulfillment_Status__c = 'Restocked';
            
        } else if (
            !isInsert &&
            ord.Financial_Status__c == 'Refunded'
        ) {
            ord.Financial_Status__c = 'Refunded';
            ord.Fulfillment_Status__c = 'Restocked';
            
        } else {
            ord.Financial_Status__c = financialStatus;
            ord.Fulfillment_Status__c = fulfillmentStatus;
        }
        
        if (isInsert) {
            insertOrderWithDuplicateRecovery(
                ord,
                squareOrderId,
                squarePaymentId,
                resolvedAccountId,
                locationId,
                financialStatus,
                fulfillmentStatus,
                totalAmount,
                squareOrder,
                paymentIsFullyRefunded,
                popUpProviderCustomerId
            );
            
        } else {
            updateOrder(ord, squareOrderId, squarePaymentId);
        }
        
        if (ord.Id != null) {
            SquareOrderItemSyncService.syncOrderItems(
                ord.Id,
                squareOrder,
                squarePricebookId,
                popUpProviderCustomerId
            );
        }
    }
    
    // ── Private: find existing Order (normal rows only) ──────────────────────
    @TestVisible
    private static Order findExistingOrder(
        String squarePaymentId,
        String squareOrderId
    ) {
        List<Order> existing = new List<Order>();
        
        if (String.isNotBlank(squarePaymentId)) {
            existing = [
                SELECT Id,
                AccountId,
                Status,
                Type,
                Pricebook2Id,
                Square_Order_Id__c,
                Square_Payment_Id__c,
                Square_Location_Id__c,
                Financial_Status__c,
                Fulfillment_Status__c,
                Shop_Total_Amount__c,
                Square_Raw_JSON__c,
                Location__c
                FROM Order
                WHERE Square_Payment_Id__c = :squarePaymentId
                LIMIT 1
            ];
        }
        
        if (existing.isEmpty() && String.isNotBlank(squareOrderId)) {
            existing = [
                SELECT Id,
                AccountId,
                Status,
                Type,
                Pricebook2Id,
                Square_Order_Id__c,
                Square_Payment_Id__c,
                Square_Location_Id__c,
                Financial_Status__c,
                Fulfillment_Status__c,
                Shop_Total_Amount__c,
                Square_Raw_JSON__c,
                Location__c
                FROM Order
                WHERE Square_Order_Id__c = :squareOrderId
                LIMIT 1
            ];
        }
        
        return existing.isEmpty() ? null : existing[0];
    }
    
    private static Id getSquarePricebookId() {
        List<Pricebook2> pricebooks = [
            SELECT Id
            FROM Pricebook2
            WHERE Name = 'Square Pricebook'
            AND IsActive = true
            LIMIT 1
        ];
        
        if (pricebooks.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'SquareOrderStatusSyncService: active Square Pricebook not found. ' +
                'Order will still be created/updated, but OrderItems will be skipped.'
            );
            return null;
        }
        
        return pricebooks[0].Id;
    }
    // ── Private: insert with race-condition duplicate recovery ───────────────
    @TestVisible
    private static void insertOrderWithDuplicateRecovery(
        Order ord,
        String squareOrderId,
        String squarePaymentId,
        Id resolvedAccountId,
        String locationId,
        String financialStatus,
        String fulfillmentStatus,
        Decimal totalAmount,
        Map<String, Object> squareOrder,
        Boolean paymentIsFullyRefunded,
        Id popUpProviderCustomerId
    ) {
        try {
            insert ord;
            
            System.debug(LoggingLevel.INFO,
                         'SquareOrderStatusSyncService: inserted Order. orderId=' +
                         ord.Id + ', squareOrderId=' + squareOrderId +
                         ', squarePaymentId=' + squarePaymentId);
            
        } catch (DmlException e) {
            
            if (e.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
                System.debug(LoggingLevel.ERROR,
                             'SquareOrderStatusSyncService: insert failed. squareOrderId=' +
                             squareOrderId + ', squarePaymentId=' + squarePaymentId +
                             ', error=' + e.getMessage());
                throw e;
            }
            
            System.debug(LoggingLevel.WARN,
                         'SquareOrderStatusSyncService: duplicate insert detected. ' +
                         'Recovering by Salesforce record ID from exception. squareOrderId=' +
                         squareOrderId + ', squarePaymentId=' + squarePaymentId +
                         ', error=' + e.getMessage());
            
            // Parse the Salesforce record ID directly from the exception message.
            // Querying by primary key (WHERE Id = :sfId) is always reliable regardless
            // of transaction isolation — unlike querying by Square IDs which returns 0
            // rows when a sibling transaction has not yet committed.
            String sfRecordId = extractSalesforceIdFromDuplicateException(e.getMessage());
            
            Order existingOrd = null;
            
            if (String.isNotBlank(sfRecordId)) {
                List<Order> byId = [
                    SELECT Id, IsDeleted, AccountId, Status, Type,
                    Square_Order_Id__c, Square_Payment_Id__c,
                    Square_Location_Id__c, Financial_Status__c,
                    Fulfillment_Status__c, Shop_Total_Amount__c,
                    Square_Raw_JSON__c
                    FROM Order
                    WHERE Id = :sfRecordId
                    LIMIT 1
                    ALL ROWS
                ];
                if (!byId.isEmpty()) {
                    existingOrd = byId[0];
                }
            }
            
            // Fallback: try by Square IDs in case regex somehow failed
            if (existingOrd == null) {
                existingOrd = findExistingOrderIncludingDeleted(
                    squarePaymentId, squareOrderId
                );
            }
            
            if (existingOrd == null) {
                System.debug(LoggingLevel.ERROR,
                             'SquareOrderStatusSyncService: duplicate insert happened but ' +
                             'existing Order could not be found even by SF Id. squareOrderId=' +
                             squareOrderId + ', squarePaymentId=' + squarePaymentId);
                return;
            }
            
            if (existingOrd.IsDeleted) {
                undelete existingOrd;
                existingOrd = [
                    SELECT Id, AccountId, Status, Type,
                    Square_Order_Id__c, Square_Payment_Id__c,
                    Square_Location_Id__c, Financial_Status__c,
                    Fulfillment_Status__c, Shop_Total_Amount__c,
                    Square_Raw_JSON__c
                    FROM Order
                    WHERE Id = :existingOrd.Id
                    LIMIT 1
                ];
            }
            
            existingOrd.AccountId             = resolvedAccountId;
            existingOrd.Square_Order_Id__c    = squareOrderId;
            existingOrd.Square_Location_Id__c = locationId;
            applyPopUpProviderToOrder(existingOrd, popUpProviderCustomerId);
            Id inventoryLocationId = InventoryRuleService.getLocationIdForOrderType('POS');
            if (inventoryLocationId != null) {
                existingOrd.Location__c = inventoryLocationId;
            }
            existingOrd.Shop_Total_Amount__c  = totalAmount;
            existingOrd.Square_Raw_JSON__c    = JSON.serialize(squareOrder);
            // FIX: activate before updating
            //existingOrd.Status                = 'Success';
            
            if (String.isNotBlank(squarePaymentId) && squarePaymentId != squareOrderId) {
                existingOrd.Square_Payment_Id__c = squarePaymentId;
            }
            
            if (paymentIsFullyRefunded) {
                existingOrd.Financial_Status__c   = 'Refunded';
                existingOrd.Fulfillment_Status__c = 'Restocked';
            } else if (existingOrd.Financial_Status__c == 'Refunded') {
                existingOrd.Financial_Status__c   = 'Refunded';
                existingOrd.Fulfillment_Status__c = 'Restocked';
            } else {
                existingOrd.Financial_Status__c   = financialStatus;
                existingOrd.Fulfillment_Status__c = fulfillmentStatus;
            }
            
            updateOrder(existingOrd, squareOrderId, squarePaymentId);

            // Carry the recovered Order Id back to the caller so the normal
            // OrderItem synchronization still runs after duplicate recovery.
            ord.Id = existingOrd.Id;
        }
    }
    
    // ── Extract SF record ID from duplicate exception message ─────────────────
    // Exception format: "...duplicates value on record with id: 801XXXXXXXXXXXXXXX: []"
    @TestVisible
    private static String extractSalesforceIdFromDuplicateException(String msg) {
        if (String.isBlank(msg)) return null;
        Pattern p = Pattern.compile('record with id: ([a-zA-Z0-9]{15,18})');
        Matcher m = p.matcher(msg);
        if (m.find()) {
            return m.group(1);
        }
        return null;
    }
    
    // ── Private: find existing Order including soft-deleted rows ─────────────
    @TestVisible
    public static Order findExistingOrderIncludingDeleted(
        String squarePaymentId,
        String squareOrderId
    ) {
        List<Order> existing = new List<Order>();
        
        if (String.isNotBlank(squarePaymentId)) {
            existing = [
                SELECT Id, IsDeleted, AccountId, Status, Type,
                Square_Order_Id__c, Square_Payment_Id__c,
                Square_Location_Id__c, Financial_Status__c,
                Fulfillment_Status__c, Shop_Total_Amount__c,
                Square_Raw_JSON__c
                FROM Order
                WHERE Square_Payment_Id__c = :squarePaymentId
                LIMIT 1
                ALL ROWS
            ];
        }
        
        if (existing.isEmpty() && String.isNotBlank(squareOrderId)) {
            existing = [
                SELECT Id, IsDeleted, AccountId, Status, Type,
                Square_Order_Id__c, Square_Payment_Id__c,
                Square_Location_Id__c, Financial_Status__c,
                Fulfillment_Status__c, Shop_Total_Amount__c,
                Square_Raw_JSON__c
                FROM Order
                WHERE Square_Order_Id__c = :squareOrderId
                LIMIT 1
                ALL ROWS
            ];
        }
        
        return existing.isEmpty() ? null : existing[0];
    }
    
    /**
     * Assigns the Customer lookup used by the Pop-up Provider field.
     * Uses describe checks so a missing field is logged rather than causing
     * an Apex compilation dependency on metadata that may differ by org.
     */
    private static void applyPopUpProviderToOrder(Order ord, Id providerCustomerId) {
        if (ord == null || providerCustomerId == null) {
            return;
        }

        Map<String, Schema.SObjectField> orderFields =
            Schema.SObjectType.Order.fields.getMap();
        String fieldApiName = 'Pop_up_Provider__c';

        if (!orderFields.containsKey(fieldApiName)) {
            System.debug(
                LoggingLevel.ERROR,
                'SquareOrderStatusSyncService: Order.Pop_up_Provider__c does not exist. ' +
                'Cannot store providerCustomerId=' + providerCustomerId
            );
            return;
        }

        Schema.SObjectField providerFieldToken = orderFields.get(fieldApiName);
        if (!SquarePopUpAccountService.isProviderCustomerReference(providerFieldToken)) {
            System.debug(
                LoggingLevel.ERROR,
                'SquareOrderStatusSyncService: Order.Pop_up_Provider__c does not reference the configured provider Customer object.'
            );
            return;
        }

        ord.put(fieldApiName, providerCustomerId);
        System.debug(
            LoggingLevel.INFO,
            'SquareOrderStatusSyncService: assigned Pop-up Provider Customer to Order. ' +
            'orderId=' + ord.Id + ', providerCustomerId=' + providerCustomerId
        );
    }

    // ── Private: update Order with logging ───────────────────────────────────
    @TestVisible
    private static void updateOrder(
        Order ord,
        String squareOrderId,
        String squarePaymentId
    ) {
        List<Database.SaveResult> results =
            Database.update(new List<Order>{ ord }, false);
        
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                System.debug(LoggingLevel.INFO,
                             'SquareOrderStatusSyncService: updated Order. orderId=' +
                             ord.Id + ', squareOrderId=' + squareOrderId +
                             ', squarePaymentId=' + squarePaymentId +
                             ', Financial_Status__c=' + ord.Financial_Status__c +
                             ', Fulfillment_Status__c=' + ord.Fulfillment_Status__c);
            } else {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(LoggingLevel.ERROR,
                                 'SquareOrderStatusSyncService: Order update failed. orderId=' +
                                 ord.Id + ', squareOrderId=' + squareOrderId +
                                 ', squarePaymentId=' + squarePaymentId +
                                 ', error=' + err.getMessage());
                }
            }
        }
    }
    
    // ── Private: field extraction helpers ────────────────────────────────────
    // ── Private: detect empty/zero-value Square order shells ─────────────────
    @TestVisible
    private static Boolean squareOrderHasLineItems(Map<String, Object> squareOrder) {
        if (squareOrder == null) return false;
        Object lineItemsObj = squareOrder.get('line_items');
        if (!(lineItemsObj instanceof List<Object>)) return false;
        List<Object> lineItems = (List<Object>) lineItemsObj;
        return !lineItems.isEmpty();
    }
    
    @TestVisible
    private static Decimal extractTotalAmount(Map<String, Object> squareOrder) {
        if (squareOrder == null) return 0;
        Map<String, Object> totalMoney =
            (Map<String, Object>) squareOrder.get('total_money');
        if (totalMoney == null || totalMoney.get('amount') == null) return 0;
        return Decimal.valueOf(String.valueOf(totalMoney.get('amount'))) / 100;
    }
    
    @TestVisible
    private static Id findPersonAccountIdBySquareCustomerId(String squareCustomerId) {
        if (String.isBlank(squareCustomerId)) return null;
        String normalizedId = squareCustomerId.trim();
        List<Account> accounts = [
            SELECT Id FROM Account
            WHERE IsPersonAccount = true
            AND Square_Customer_Id__c = :normalizedId
            LIMIT 1
        ];
        if (!accounts.isEmpty()) return accounts[0].Id;
        System.debug(LoggingLevel.ERROR,
                     'SquareOrderStatusSyncService: no Person Account found for ' +
                     'Square_Customer_Id__c=' + normalizedId);
        return null;
    }
    
    @TestVisible
    private static String extractCustomerIdFromSquareOrder(
        Map<String, Object> squareOrder
    ) {
        if (squareOrder == null) return null;
        
        if (squareOrder.get('customer_id') != null) {
            return String.valueOf(squareOrder.get('customer_id'));
        }
        
        List<Object> tenders = (List<Object>) squareOrder.get('tenders');
        if (tenders != null) {
            for (Object tenderObj : tenders) {
                if (!(tenderObj instanceof Map<String, Object>)) continue;
                Map<String, Object> tender = (Map<String, Object>) tenderObj;
                if (tender.get('customer_id') != null) {
                    return String.valueOf(tender.get('customer_id'));
                }
            }
        }
        return null;
    }
    
    @TestVisible
    private static String extractPaymentIdFromSquareOrder(
        Map<String, Object> squareOrder
    ) {
        if (squareOrder == null) return null;
        
        List<Object> tenders = (List<Object>) squareOrder.get('tenders');
        if (tenders == null) return null;
        
        String squareOrderId = squareOrder.get('id') == null
            ? null : String.valueOf(squareOrder.get('id'));
        
        for (Object tenderObj : tenders) {
            if (!(tenderObj instanceof Map<String, Object>)) continue;
            Map<String, Object> tender = (Map<String, Object>) tenderObj;
            if (tender.get('payment_id') != null) {
                String paymentId = String.valueOf(tender.get('payment_id'));
                if (String.isNotBlank(paymentId) && paymentId != squareOrderId) {
                    return paymentId;
                }
            }
        }
        return null;
    }
    
    @TestVisible
    private static Boolean isSquarePaymentFullyRefunded(String squarePaymentId) {
        if (String.isBlank(squarePaymentId)) return false;
        try {
            Map<String, Object> payment =
                SquareApiClient.retrievePayment(squarePaymentId);
            if (payment == null) return false;
            
            Decimal paymentAmount  = extractMoneyAmount(payment, 'amount_money');
            Decimal refundedAmount = extractMoneyAmount(payment, 'refunded_money');
            
            System.debug(LoggingLevel.INFO,
                         'SquareOrderStatusSyncService: payment refund check. paymentId=' +
                         squarePaymentId +
                         ', paymentAmount=' + paymentAmount +
                         ', refundedAmount=' + refundedAmount);
            
            return paymentAmount > 0 && refundedAmount >= paymentAmount;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                         'SquareOrderStatusSyncService: payment refund check failed. paymentId=' +
                         squarePaymentId + ', error=' + e.getMessage());
            return false;
        }
    }
    
    @TestVisible
    private static Decimal extractMoneyAmount(
        Map<String, Object> root,
        String fieldName
    ) {
        if (root == null || String.isBlank(fieldName)) return 0;
        if (root.get(fieldName) == null) return 0;
        Map<String, Object> money = (Map<String, Object>) root.get(fieldName);
        if (money == null || money.get('amount') == null) return 0;
        return Decimal.valueOf(String.valueOf(money.get('amount')));
    }
    
    @TestVisible
    private static String mapFinancialStatus(Map<String, Object> squareOrder) {
        String state = (String) squareOrder.get('state');
        if (state == 'COMPLETED') return 'Paid';
        if (state == 'CANCELED')  return 'Refunded';
        return 'Pending';
    }
    
    @TestVisible
    private static String mapFulfillmentStatus(
        Map<String, Object> squareOrder,
        String financialStatus
    ) {
        return (financialStatus == 'Paid') ? 'Fulfilled' : 'Unfulfilled';
    }
}