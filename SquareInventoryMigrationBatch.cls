public without sharing class SquareInventoryMigrationBatch
    implements Database.Batchable<SObject>,
               Database.AllowsCallouts {

    private static final String INVENTORY_ENDPOINT =
        'callout:Square_API/v2/inventory/changes/batch-create';

    /*
     * Square Inventory API inventory state.
     */
    private static final String INVENTORY_STATE =
        'IN_STOCK';

    public Database.QueryLocator start(
        Database.BatchableContext context
    ) {
        /*
         * Assumptions based on the current integration:
         *
         * Inventory__c.Available__c
         * Inventory__c.Variant__c -> Product2
         * Inventory__c.Location__c -> Location
         * Product2.Square_Catalog_Variation_Id__c
         * Location.Square_Location_ID__c
         *
         * If your Square location field uses a different API name,
         * change only Location__r.Square_Location_ID__c below.
         */
        return Database.getQueryLocator([
            SELECT Id,
                   Available__c,
                   Variant__c,
                   Variant__r.Name,
                   Variant__r.StockKeepingUnit,
                   Variant__r.Square_Catalog_Variation_Id__c,
                   Location__c,
                   Location__r.Name,
                   Location__r.Square_Location_ID__c
            FROM Inventory__c
            WHERE Variant__c != null
            AND Variant__r.Square_Catalog_Variation_Id__c != null
            AND Location__c != null
            AND Location__r.Square_Location_ID__c != null
            ORDER BY Id
        ]);
    }

    public void execute(
        Database.BatchableContext context,
        List<SObject> scope
    ) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        List<Object> changes =
            new List<Object>();

        Map<Integer, Id> inventoryIdByChangeIndex =
            new Map<Integer, Id>();

        for (SObject scopeRecord : scope) {
            Inventory__c inventory =
                (Inventory__c) scopeRecord;

            if (
                inventory == null ||
                inventory.Variant__r == null ||
                inventory.Location__r == null
            ) {
                continue;
            }

            String squareVariationId =
                inventory.Variant__r
                    .Square_Catalog_Variation_Id__c;

            String squareLocationId =
                inventory.Location__r
                    .Square_Location_ID__c;

            if (
                String.isBlank(squareVariationId) ||
                String.isBlank(squareLocationId)
            ) {
                continue;
            }

            Decimal availableQuantity =
                inventory.Available__c == null
                    ? 0
                    : inventory.Available__c;

            Integer changeIndex =
                changes.size();

            inventoryIdByChangeIndex.put(
                changeIndex,
                inventory.Id
            );

            changes.add(
                new Map<String, Object>{
                    'type' => 'PHYSICAL_COUNT',

                    'physical_count' =>
                        new Map<String, Object>{
                            'catalog_object_id' =>
                                squareVariationId,

                            'location_id' =>
                                squareLocationId,

                            /*
                             * Square expects quantity as a string.
                             */
                            'quantity' =>
                                formatQuantity(
                                    availableQuantity
                                ),

                            'state' =>
                                INVENTORY_STATE,

                            'occurred_at' =>
                                formatSquareDatetime(
                                    System.now()
                                )
                        }
                }
            );
        }

        if (changes.isEmpty()) {
            return;
        }

        Map<String, Object> requestPayload =
            new Map<String, Object>{
                'idempotency_key' =>
                    createIdempotencyKey(
                        context,
                        scope
                    ),

                'changes' => changes,

                /*
                 * true means Square ignores changes whose timestamps
                 * are older than the current Square inventory state.
                 */
                'ignore_unchanged_counts' => true
            };

        HttpRequest request =
            new HttpRequest();

        request.setEndpoint(
            INVENTORY_ENDPOINT
        );

        request.setMethod('POST');

        request.setHeader(
            'Content-Type',
            'application/json'
        );

        request.setHeader(
            'Accept',
            'application/json'
        );

        request.setTimeout(120000);

        request.setBody(
            JSON.serialize(
                requestPayload
            )
        );

        HttpResponse response =
            new Http().send(request);

        Integer statusCode =
            response.getStatusCode();

        if (
            statusCode < 200 ||
            statusCode >= 300
        ) {
            throw new SquareInventoryMigrationException(
                'Square inventory migration failed. ' +
                'Status=' + statusCode +
                ', Body=' + response.getBody() +
                ', InventoryIds=' +
                inventoryIdByChangeIndex.values()
            );
        }

        Map<String, Object> responsePayload =
            deserializeResponse(
                response.getBody()
            );

        List<Object> errors =
            responsePayload == null
                ? null
                : (List<Object>)
                    responsePayload.get('errors');

        if (
            errors != null &&
            !errors.isEmpty()
        ) {
            throw new SquareInventoryMigrationException(
                'Square inventory migration returned errors. ' +
                JSON.serialize(errors)
            );
        }

        System.debug(
            LoggingLevel.INFO,
            'Square inventory migration completed. ' +
            'InventoryIds=' +
            inventoryIdByChangeIndex.values() +
            ', ChangeCount=' +
            changes.size() +
            ', Status=' +
            statusCode
        );
    }

    public void finish(
        Database.BatchableContext context
    ) {
        System.debug(
            LoggingLevel.INFO,
            'Square inventory migration Batch completed.'
        );
    }

    /*
     * Preserve whole quantities without scientific notation.
     * Decimal quantities are also retained when applicable.
     */
    @TestVisible
    private static String formatQuantity(
        Decimal quantity
    ) {
        if (quantity == null) {
            return '0';
        }

        Decimal normalized =
            quantity.stripTrailingZeros();

        return normalized.toPlainString();
    }

    @TestVisible
    private static String formatSquareDatetime(
        Datetime value
    ) {
        Datetime effectiveValue =
            value == null
                ? System.now()
                : value;

        return effectiveValue.formatGMT(
            'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
        );
    }

    @TestVisible
    private static String createIdempotencyKey(
        Database.BatchableContext context,
        List<SObject> scope
    ) {
        String jobId =
            context == null
                ? 'NO_JOB'
                : String.valueOf(
                    context.getJobId()
                );

        String firstRecordId =
            scope == null ||
            scope.isEmpty() ||
            scope[0] == null
                ? 'NO_RECORD'
                : String.valueOf(
                    scope[0].get('Id')
                );

        String rawValue =
            jobId +
            '-' +
            firstRecordId +
            '-' +
            String.valueOf(
                System.now().getTime()
            );

        /*
         * Square idempotency keys have a limited length.
         */
        return EncodingUtil.convertToHex(
            Crypto.generateDigest(
                'SHA-256',
                Blob.valueOf(rawValue)
            )
        );
    }

    @TestVisible
    private static Map<String, Object>
        deserializeResponse(
            String responseBody
        ) {
        if (String.isBlank(responseBody)) {
            return new Map<String, Object>();
        }

        Object parsed =
            JSON.deserializeUntyped(
                responseBody
            );

        try {
            return (Map<String, Object>) parsed;
        } catch (Exception e) {
            throw new SquareInventoryMigrationException(
                'Unexpected Square inventory response: ' +
                responseBody
            );
        }
    }

    public class SquareInventoryMigrationException
        extends Exception {
    }
}