@RestResource(urlMapping='/square/catalog/*')
global without sharing class SquareCatalogWebhookRestResource {

    @HttpPost
    global static void receiveWebhook() {
        String body = RestContext.request.requestBody.toString();
        System.debug('Square Catalog Webhook Body: ' + body);

        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(body);

        String eventType = (String) payload.get('type');

        if (eventType == 'catalog.version.updated') {
            EventBus.publish(new Square_Catalog_Sync_Event__e());
        }

        RestContext.response.statusCode = 200;
    }
}