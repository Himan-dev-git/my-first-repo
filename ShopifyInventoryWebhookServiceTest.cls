@IsTest
private class ShopifyInventoryWebhookServiceTest {

    private static Integer counter = 0;
    private static User shopifyWebhookUser;

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────

    private static String uniqueText(String prefix) {
        counter++;
        return prefix + '-' + String.valueOf(DateTime.now().getTime()) + '-' + counter;
    }

    private static String uniqueNumericText() {
        counter++;
        return String.valueOf(DateTime.now().getTime()) + String.valueOf(counter);
    }

    private static void setMock() {
        GlobalHttpMock.mockMode = 'SUCCESS';
        Test.setMock(HttpCalloutMock.class, new GlobalHttpMock());
    }

    private static Boolean fieldExists(String objectApiName, String fieldApiName) {
        return Schema.getGlobalDescribe().containsKey(objectApiName) &&
            Schema.getGlobalDescribe()
                .get(objectApiName)
                .getDescribe()
                .fields
                .getMap()
                .containsKey(fieldApiName);
    }

    private static User getShopifyWebhookUser() {
        if (shopifyWebhookUser != null) {
            return shopifyWebhookUser;
        }

        String suffix = String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Math.abs(Crypto.getRandomInteger()));

        User u = new User(
            FirstName = 'Shopify',
            LastName = 'Webhook Site',
            Alias = 'shpwhk',
            Email = 'shopify_webhook_site_' + suffix + '@test.com',
            Username = 'shopify_webhook_site_' + suffix + '@test.com',
            CommunityNickname = ('shopifywebhook' + suffix).left(40),
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        insert u;
        shopifyWebhookUser = u;
        return shopifyWebhookUser;
    }

    private static Id getVariantRecordTypeIdOrNull() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Product2'
            AND DeveloperName = 'Variant'
            LIMIT 1
        ];

        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Product2 createVariant(String variantShopId) {
        Product2 parentProduct = new Product2(
            Name = uniqueText('Parent Product'),
            IsActive = true,
            Shop_Id__c = 'PARENT-' + variantShopId,
            Updated_by_Integration__c = true
        );

        if (fieldExists('Product2', 'Type__c')) {
            parentProduct.put('Type__c', 'Product');
        }

        Product2 variant = new Product2(
            Name = uniqueText('Variant Product'),
            IsActive = true,
            Shop_Id__c = variantShopId,
            Updated_by_Integration__c = true
        );

        if (fieldExists('Product2', 'Type__c')) {
            variant.put('Type__c', 'Variant');
        }

        Id variantRecordTypeId = getVariantRecordTypeIdOrNull();
        if (variantRecordTypeId != null) {
            variant.RecordTypeId = variantRecordTypeId;
        }

        System.runAs(getShopifyWebhookUser()) {
            insert parentProduct;

            variant.Parent__c = parentProduct.Id;
            insert variant;
        }

        return variant;
    }

    private static Inventory__c createInventoryRow(
        String inventoryItemId,
        String locationId,
        Decimal availableQty
    ) {
        Product2 variant = createVariant(uniqueNumericText());

        InventorySyncControl.skipOutbound = true;

        Inventory__c inv = new Inventory__c(
            Variant__c = variant.Id,
            Shopify_Inventory_Item_ID__c = inventoryItemId,
            Shopify_Location_ID__c = locationId,
            Available__c = availableQty,
            Sync_Status__c = 'Synced'
        );

        if (fieldExists('Inventory__c', 'Inventory_Key__c')) {
            inv.put(
                'Inventory_Key__c',
                String.valueOf(variant.Id) + '-' + locationId + '-' + uniqueNumericText()
            );
        }

        insert inv;

        InventorySyncControl.skipOutbound = false;

        return inv;
    }

    private static void processInboundWebhook(String jsonPayload) {
        setMock();

        InventorySyncControl.skipOutbound = true;

        try {
            ShopifyInventoryWebhookService.process(jsonPayload);
        } finally {
            InventorySyncControl.skipOutbound = false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testProcess_UpdatesExistingInventory() {
        Inventory__c inv = createInventoryRow('INVITEM-1', 'LOC-1', 5);

        String jsonPayload = JSON.serialize(new Map<String, Object>{
            'inventory_item_id' => 'INVITEM-1',
            'location_id' => 'LOC-1',
            'available' => 12
        });

        Test.startTest();
        processInboundWebhook(jsonPayload);
        Test.stopTest();

        Inventory__c updated = [
            SELECT Available__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];

        System.assertEquals(12, updated.Available__c);
        System.assertEquals('Success', updated.Sync_Status__c);
        System.assertNotEquals(null, updated.Last_Sync_At__c);
    }

    @IsTest
    static void testProcess_DecimalAvailable() {
        Inventory__c inv = createInventoryRow('INVITEM-DECIMAL', 'LOC-DECIMAL', 5);

        String jsonPayload = JSON.serialize(new Map<String, Object>{
            'inventory_item_id' => 'INVITEM-DECIMAL',
            'location_id' => 'LOC-DECIMAL',
            'available' => 7.5
        });

        Test.startTest();
        processInboundWebhook(jsonPayload);
        Test.stopTest();

        Inventory__c updated = [
            SELECT Available__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];

        System.assertEquals(7.5, updated.Available__c);
        System.assertEquals('Success', updated.Sync_Status__c);
        System.assertNotEquals(null, updated.Last_Sync_At__c);
    }

    @IsTest
    static void testProcess_ZeroAvailable() {
        Inventory__c inv = createInventoryRow('INVITEM-ZERO', 'LOC-ZERO', 9);

        String jsonPayload = JSON.serialize(new Map<String, Object>{
            'inventory_item_id' => 'INVITEM-ZERO',
            'location_id' => 'LOC-ZERO',
            'available' => 0
        });

        Test.startTest();
        processInboundWebhook(jsonPayload);
        Test.stopTest();

        Inventory__c updated = [
            SELECT Available__c, Sync_Status__c, Last_Sync_At__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];

        System.assertEquals(0, updated.Available__c);
        System.assertEquals('Success', updated.Sync_Status__c);
        System.assertNotEquals(null, updated.Last_Sync_At__c);
    }

    @IsTest
    static void testProcess_NoMatchingInventory_DoesNothing() {
        String jsonPayload = JSON.serialize(new Map<String, Object>{
            'inventory_item_id' => 'NO-MATCH',
            'location_id' => 'NO-LOCATION',
            'available' => 20
        });

        Test.startTest();
        processInboundWebhook(jsonPayload);
        Test.stopTest();

        List<Inventory__c> rows = [
            SELECT Id
            FROM Inventory__c
            WHERE Shopify_Inventory_Item_ID__c = 'NO-MATCH'
        ];

        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void testProcess_LocationMismatchDoesNothing() {
        Inventory__c inv = createInventoryRow('INVITEM-MISMATCH', 'LOC-CORRECT', 5);

        String jsonPayload = JSON.serialize(new Map<String, Object>{
            'inventory_item_id' => 'INVITEM-MISMATCH',
            'location_id' => 'LOC-WRONG',
            'available' => 99
        });

        Test.startTest();
        processInboundWebhook(jsonPayload);
        Test.stopTest();

        Inventory__c unchanged = [
            SELECT Available__c, Sync_Status__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];

        System.assertEquals(5, unchanged.Available__c);
        System.assertEquals('Synced', unchanged.Sync_Status__c);
    }

    @IsTest
    static void testProcess_InventoryItemMismatchDoesNothing() {
        Inventory__c inv = createInventoryRow('INVITEM-CORRECT', 'LOC-ITEM-MISMATCH', 5);

        String jsonPayload = JSON.serialize(new Map<String, Object>{
            'inventory_item_id' => 'INVITEM-WRONG',
            'location_id' => 'LOC-ITEM-MISMATCH',
            'available' => 99
        });

        Test.startTest();
        processInboundWebhook(jsonPayload);
        Test.stopTest();

        Inventory__c unchanged = [
            SELECT Available__c, Sync_Status__c
            FROM Inventory__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];

        System.assertEquals(5, unchanged.Available__c);
        System.assertEquals('Synced', unchanged.Sync_Status__c);
    }
}