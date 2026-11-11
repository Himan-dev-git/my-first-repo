global without sharing class SquarePricebookSyncScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        Integer runningJobs = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'SquarePricebookSyncQueueable'
            AND Status IN ('Queued', 'Processing', 'Preparing')
        ];

        if (runningJobs == 0) {
            System.enqueueJob(new SquarePricebookSyncQueueable());
        }
    }
}