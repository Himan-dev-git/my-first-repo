@RestResource(urlMapping='/events')
global without sharing class RestEndpoint_Events {

    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = WebhookHelper.handleWebhookRequest(req);
        RestContext.response = res;
    }
}