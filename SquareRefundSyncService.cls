public without sharing class SquareRefundSyncService {
    
    public static Boolean syncRefund(
        String refundId,
        String eventType,
        String rawPayload
    ) {
        if (String.isBlank(refundId)) {
            return true;
        }
        
        Map<String, Object> refund = SquareApiClient.retrieveRefund(refundId);
        
        if (refund == null) {
            System.debug(LoggingLevel.WARN,
                         'SquareRefundSyncService: refund not found. refundId=' + refundId
                        );
            return true;
        }
        
        String status    = (String) refund.get('status');
        String paymentId = (String) refund.get('payment_id');
        String orderId   = (String) refund.get('order_id');
        
        String reason;
        if (refund.get('reason') != null) {
            reason = String.valueOf(refund.get('reason'));
        }
        
        Decimal refundAmount;
        Map<String, Object> amountMoney =
            (Map<String, Object>) refund.get('amount_money');
        
        if (
            amountMoney != null &&
            amountMoney.get('amount') != null
        ) {
            refundAmount =
                Decimal.valueOf(String.valueOf(amountMoney.get('amount'))) / 100;
        }
        
        Datetime refundDate;
        
        if (refund.get('created_at') != null) {
            refundDate = parseSquareDatetime(String.valueOf(refund.get('created_at')));
            
        } else if (refund.get('updated_at') != null) {
            refundDate = parseSquareDatetime(String.valueOf(refund.get('updated_at')));
            
        } else {
            refundDate = System.now();
        }
        
        System.debug(LoggingLevel.INFO,
                     'Square refund sync. refundId=' + refundId +
                     ', status=' + status +
                     ', paymentId=' + paymentId +
                     ', refundOrderId=' + orderId +
                     ', refundDate=' + refundDate +
                     ', refundReason=' + reason +
                     ', refundAmount=' + refundAmount
                    );
        
        Order ord = findOrderForRefund(paymentId, orderId);
        
        if (ord == null) {
            System.debug(LoggingLevel.WARN,
                         'Square refund received but no Salesforce Order found. ' +
                         'paymentId=' + paymentId +
                         ', refundOrderId=' + orderId +
                         ', refundId=' + refundId
                        );
            
            return false;
        }
        
        if (String.isNotBlank(paymentId)) {
            ord.Square_Payment_Id__c = paymentId;
        }
        
        /*
* Populate refund fields as soon as refund.created or refund.updated arrives.
* This should happen even when Square refund status is PENDING.
*/
        ord.Refund_Date__c = refundDate;
        ord.Refund_Reason__c = reason;
        
        if (refundAmount != null) {
            ord.Refund_Amount__c = refundAmount;
        }
        
        /*
* Only mark the Order as fully refunded/restocked when Square says
* the refund is COMPLETED.
*/
        if (status == 'COMPLETED') {
            ord.Financial_Status__c = 'Refunded';
            ord.Fulfillment_Status__c = 'Restocked';
        }
        
        List<Database.SaveResult> results =
            Database.update(new List<Order>{ ord }, false);
        
        Boolean updated = false;
        
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                updated = true;
                
                System.debug(LoggingLevel.INFO,
                             'Square refund fields applied. orderId=' +
                             ord.Id +
                             ', paymentId=' +
                             paymentId +
                             ', refundId=' +
                             refundId +
                             ', refundStatus=' +
                             status +
                             ', refundDate=' +
                             refundDate +
                             ', refundReason=' +
                             reason +
                             ', refundAmount=' +
                             refundAmount
                            );
                
            } else {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(LoggingLevel.ERROR,
                                 'Square refund order update failed. orderId=' +
                                 ord.Id +
                                 ', paymentId=' +
                                 paymentId +
                                 ', refundId=' +
                                 refundId +
                                 ', error=' +
                                 err.getMessage()
                                );
                }
            }
        }
        
        return updated;
    }
    
    private static Datetime parseSquareDatetime(String squareDateTime) {
    if (String.isBlank(squareDateTime)) {
        return System.now();
    }

    String normalizedValue = squareDateTime;

    if (normalizedValue.endsWith('Z')) {
        normalizedValue = normalizedValue.replace('Z', '');
    }

    if (normalizedValue.contains('.')) {
        normalizedValue = normalizedValue.substringBefore('.');
    }

    normalizedValue = normalizedValue.replace('T', ' ');

    try {
        return Datetime.valueOfGmt(normalizedValue);
    } catch (Exception e) {
        System.debug(
            LoggingLevel.WARN,
            'SquareRefundSyncService: failed to parse refund datetime. value=' +
            squareDateTime +
            ', error=' +
            e.getMessage()
        );

        return System.now();
    }
}
    
    
    private static Order findOrderForRefund(
        String paymentId,
        String refundOrderId
    ) {
        List<Order> orders = new List<Order>();
        
        if (String.isNotBlank(paymentId)) {
            orders = [
                SELECT Id,
                Status,
                Square_Payment_Id__c,
                Square_Order_Id__c,
                Financial_Status__c,
                Fulfillment_Status__c,
                Refund_Date__c,
                Refund_Reason__c,
                Refund_Amount__c
                FROM Order
                WHERE Square_Payment_Id__c = :paymentId
                LIMIT 1
            ];
        }
        
        if (!orders.isEmpty()) {
            return orders[0];
        }
        
        if (String.isNotBlank(paymentId)) {
            try {
                Map<String, Object> payment =
                    SquareApiClient.retrievePayment(paymentId);
                
                if (payment != null && payment.get('order_id') != null) {
                    String originalOrderId =
                        String.valueOf(payment.get('order_id'));
                    
                    System.debug(LoggingLevel.INFO,
                                 'Square refund fallback. paymentId=' + paymentId +
                                 ', originalOrderId from payment=' + originalOrderId
                                );
                    
                    if (String.isNotBlank(originalOrderId)) {
                        orders = [
                            SELECT Id,
                            Status,
                            Square_Payment_Id__c,
                            Square_Order_Id__c,
                            Financial_Status__c,
                            Fulfillment_Status__c,
                            Refund_Date__c,
                            Refund_Reason__c,
                            Refund_Amount__c
                            FROM Order
                            WHERE Square_Order_Id__c = :originalOrderId
                            LIMIT 1
                        ];
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                             'Square refund fallback payment lookup failed. paymentId=' +
                             paymentId +
                             ', error=' +
                             e.getMessage()
                            );
            }
        }
        
        if (!orders.isEmpty()) {
            return orders[0];
        }
        
        if (String.isNotBlank(refundOrderId)) {
            orders = [
                SELECT Id,
                Status,
                Square_Payment_Id__c,
                Square_Order_Id__c,
                Financial_Status__c,
                Fulfillment_Status__c
                FROM Order
                WHERE Square_Order_Id__c = :refundOrderId
                LIMIT 1
            ];
        }
        
        return orders.isEmpty() ? null : orders[0];
    }
}