public class SquareInventoryDeductionQueueable implements Queueable, Database.AllowsCallouts {

    private String paymentId;

    public SquareInventoryDeductionQueueable(String paymentId) {
        this.paymentId = paymentId;
    }

    public void execute(QueueableContext context) {
        SquareInventoryDeductionService.deductInventoryForPayment(paymentId);
    }
}