public class SquarePaymentQueueable implements Queueable, Database.AllowsCallouts {

    private String paymentId;

    public SquarePaymentQueueable(String paymentId) {
        this.paymentId = paymentId;
    }

    public void execute(QueueableContext context) {
    if (String.isBlank(paymentId)) return;

    // ═══════════════════════════════════════════════════════════════
    // STEP 1 — ALL CALLOUTS before any DML
    // ═══════════════════════════════════════════════════════════════

    Map<String, Object> payment;

    try {
        payment = SquareApiClient.retrievePayment(paymentId);
    } catch (Exception e) {
        System.debug(
            LoggingLevel.ERROR,
            'SquarePaymentQueueable: could not retrieve payment ' +
            paymentId +
            ' — ' +
            e.getMessage()
        );
        return;
    }

    if (payment == null) {
        System.debug(
            LoggingLevel.ERROR,
            'SquarePaymentQueueable: null payment returned for ' + paymentId
        );
        return;
    }

    String squareOrderId = (String) payment.get('order_id');

    Map<String, Object> squareOrder = null;

    if (String.isNotBlank(squareOrderId)) {
        try {
            squareOrder = SquareApiClient.retrieveOrder(squareOrderId);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'SquarePaymentQueueable: could not retrieve Square order ' +
                squareOrderId +
                ' — ' +
                e.getMessage()
            );
        }
    }

    String squareCustomerId = (String) payment.get('customer_id');

    if (String.isBlank(squareCustomerId) && squareOrder != null) {
        squareCustomerId = extractCustomerIdFromOrder(squareOrder);
    }

    Map<String, Object> squareCustomer = null;

    if (String.isNotBlank(squareCustomerId)) {
        try {
            squareCustomer = SquareApiClient.retrieveCustomer(squareCustomerId);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'SquarePaymentQueueable: could not retrieve Square customer ' +
                squareCustomerId +
                ' — ' +
                e.getMessage()
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // STEP 2 — Person Account DML first
    //
    // This fixes the current issue:
    // Order was created before the Square customer became a Person Account,
    // so the order fell back to the default Square POS Customer account.
    //
    // This method does not perform callouts because squareCustomer is already
    // pre-fetched above.
    // ═══════════════════════════════════════════════════════════════

    Id squarePersonAccountId;

    if (String.isNotBlank(squareCustomerId) && squareCustomer != null) {
        try {
            squarePersonAccountId =
                SquareCustomerConsentService.createContactFromPaymentIfConsented(
                    paymentId,
                    payment,
                    squareCustomer
                );

            System.debug(
                LoggingLevel.INFO,
                'SquarePaymentQueueable: Person Account synced before Order sync. ' +
                'paymentId=' +
                paymentId +
                ', squareCustomerId=' +
                squareCustomerId +
                ', accountId=' +
                squarePersonAccountId
            );

        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'SquarePaymentQueueable: Person Account sync failed before Order sync. ' +
                'paymentId=' +
                paymentId +
                ', squareCustomerId=' +
                squareCustomerId +
                ', error=' +
                e.getMessage()
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // STEP 3 — Order DML after Person Account exists
    //
    // SquareOrderSyncService already creates/updates Order and calls
    // SquareOrderItemSyncService.syncOrderItems().
    // ═══════════════════════════════════════════════════════════════

    try {
        SquareOrderSyncService.syncPaymentToOrder(
            paymentId,
            payment,
            squareOrder
        );

    } catch (Exception e) {
        System.debug(
            LoggingLevel.ERROR,
            'SquarePaymentQueueable: syncPaymentToOrder failed for ' +
            paymentId +
            ' — ' +
            e.getMessage()
        );
    }
}

    private static String extractCustomerIdFromOrder(Map<String, Object> squareOrder) {
        if (squareOrder == null) return null;

        if (squareOrder.get('customer_id') != null) {
            return (String) squareOrder.get('customer_id');
        }

        Object tendersObj = squareOrder.get('tenders');
        if (tendersObj == null) return null;

        for (Object tenderObj : (List<Object>) tendersObj) {
            Map<String, Object> tender = (Map<String, Object>) tenderObj;
            if (tender != null && tender.get('customer_id') != null) {
                return (String) tender.get('customer_id');
            }
        }

        return null;
    }
}