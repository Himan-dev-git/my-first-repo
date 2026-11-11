/**
 * NEW CLASS — SquareCustomerConsentQueueable
 *
 * Runs Account/Person Account DML in its own transaction, completely
 * isolated from the Order DML in SquarePaymentQueueable.
 *
 * WHY THIS EXISTS:
 * SquareCustomerConsentService.createContactFromPaymentIfConsented calls
 * Database.update on a Person Account. In this org, that operation throws
 * System.TypeException: DML operation UPDATE not allowed on Account
 * regardless of allOrNone mode, because TypeException is not a DmlException
 * and is not suppressed by partial DML mode.
 *
 * When that exception was in the same transaction as the Order insert/update,
 * it rolled back the Order, leaving the database empty and causing every
 * subsequent refund and order.updated job to find 0 rows.
 *
 * By moving Account DML here, the Order transaction commits safely first.
 * If this job fails, only the Account update rolls back — not the Order.
 */
public class SquareCustomerConsentQueueable implements Queueable {

    private String paymentId;
    private Map<String, Object> payment;
    private Map<String, Object> squareCustomer;

    public SquareCustomerConsentQueueable(
        String paymentId,
        Map<String, Object> payment,
        Map<String, Object> squareCustomer
    ) {
        this.paymentId      = paymentId;
        this.payment        = payment;
        this.squareCustomer = squareCustomer;
    }

    public void execute(QueueableContext context) {
        if (String.isBlank(paymentId) || payment == null) return;

        try {
            SquareCustomerConsentService.createContactFromPaymentIfConsented(
                paymentId,
                payment,
                squareCustomer
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'SquareCustomerConsentQueueable: consent sync failed for paymentId=' +
                paymentId + ' — ' + e.getMessage());
            // Do not rethrow — this job failing should never affect Order status.
        }
    }
}