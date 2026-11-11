global class SquareCatalogScheduler implements Schedulable {

    private Set<String> variantShopIds;

    global SquareCatalogScheduler() {}

    global SquareCatalogScheduler(Set<String> variantShopIds) {
        this.variantShopIds = variantShopIds;
    }

    global void execute(SchedulableContext sc) {
        if (variantShopIds != null && !variantShopIds.isEmpty()) {
            System.enqueueJob(new SquareCatalogQueueable(variantShopIds));
        }
    }

    public static void scheduleSync(Set<String> variantShopIds) {
        if (variantShopIds == null || variantShopIds.isEmpty()) return;

        List<String> sortedIds = new List<String>();
        sortedIds.addAll(variantShopIds);
        sortedIds.sort();

        String rawKey = String.join(sortedIds, '|');

        String hashKey = EncodingUtil.convertToHex(
            Crypto.generateDigest('MD5', Blob.valueOf(rawKey))
        ).substring(0, 12);

        Datetime runTime = System.now().addMinutes(1);

        String minuteKey = runTime.format('yyyyMMddHHmm');

        String jobName = 'Square Catalog Sync ' + hashKey + ' ' + minuteKey;

        String cron =
            runTime.second() + ' ' +
            runTime.minute() + ' ' +
            runTime.hour() + ' ' +
            runTime.day() + ' ' +
            runTime.month() + ' ? ' +
            runTime.year();

        try {
            System.schedule(
                jobName,
                cron,
                new SquareCatalogScheduler(variantShopIds)
            );
        } catch (Exception e) {
            System.debug('Square sync already scheduled for this product/minute: ' + e.getMessage());
        }
    }
}