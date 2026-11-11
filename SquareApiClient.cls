public without sharing class SquareApiClient {
    
    public static Map<String, Object> retrievePayment(String paymentId) {
        if (String.isBlank(paymentId)) return null;
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'callout:Square_API/v2/payments/' +
            EncodingUtil.urlEncode(paymentId, 'UTF-8')
        );
        req.setMethod('GET');
        req.setHeader('Square-Version', '2026-01-22');
        req.setHeader('Content-Type', 'application/json');
        //req.setHeader('Authorization', 'Bearer EAAAl4spqzyO-LBuenGf3L7SSavvYW2xzF0-X4UpIseUgt6A4EndMcn55dqyiiMX');
        
        HttpResponse res = new Http().send(req);
        
        System.debug(LoggingLevel.INFO,
                     'Square retrievePayment response. paymentId=' + paymentId +
                     ', statusCode=' + res.getStatusCode() +
                     ', body=' + res.getBody());
        
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Square payment retrieve failed. Status=' +
                res.getStatusCode() + ', Body=' + res.getBody()
            );
        }
        
        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (Map<String, Object>) root.get('payment');
    }
    
    public static Map<String, Object> retrieveTeamMember(String teamMemberId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_API/v2/team-members/' +
                        EncodingUtil.urlEncode(teamMemberId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Square-Version', '2026-01-22');
        //req.setHeader('Authorization', 'Bearer EAAAl4spqzyO-LBuenGf3L7SSavvYW2xzF0-X4UpIseUgt6A4EndMcn55dqyiiMX');
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        System.debug('Team Member Response: ' + res.getBody());
        
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Square Team Member API failed. Status=' + res.getStatusCode() +
                ', Body=' + res.getBody()
            );
        }
        
        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (Map<String, Object>) root.get('team_member');
    }
    
public static Map<String, Object> upsertCatalogObject(
    Map<String, Object> catalogObject
) {
    HttpResponse firstResponse = sendCatalogUpsertRequest(catalogObject);

    if (isSuccessfulResponse(firstResponse)) {
        return parseResponse(firstResponse);
    }

    if (
        isSquareVersionMismatch(firstResponse) &&
        catalogObject != null
    ) {
        refreshCatalogObjectVersions(catalogObject);

        HttpResponse retryResponse =
            sendCatalogUpsertRequest(catalogObject);

        if (isSuccessfulResponse(retryResponse)) {
            return parseResponse(retryResponse);
        }

        throw new CalloutException(
            'Square catalog upsert failed after refreshing versions. ' +
            'Status=' + retryResponse.getStatusCode() +
            ', Body=' + retryResponse.getBody()
        );
    }
    
    throw new CalloutException(
        'Square catalog upsert failed. Status=' +
        firstResponse.getStatusCode() +
        ', Body=' +
        firstResponse.getBody()
    );
}
    
    @TestVisible
    private static Boolean isSuccessfulResponse(HttpResponse response) {
        return response != null &&
            response.getStatusCode() >= 200 &&
            response.getStatusCode() < 300;
    }
    
    @TestVisible
    private static void refreshCatalogObjectVersions(
        Map<String, Object> outgoingObject
    ) {
        if (
            outgoingObject == null ||
            outgoingObject.get('id') == null
        ) {
            return;
        }
        
        String itemId = String.valueOf(outgoingObject.get('id'));
        
        if (String.isBlank(itemId) || itemId.startsWith('#')) {
            return;
        }
        
        Map<String, Object> latestResponse =
            retrieveCatalogObject(itemId);
        
        Map<String, Object> latestItem =
            latestResponse == null
            ? null
            : (Map<String, Object>) latestResponse.get('object');
        
        if (latestItem == null) {
            throw new CalloutException(
                'Square catalog item was not returned for ID ' + itemId
            );
        }
        
        copyVersion(latestItem, outgoingObject);
        
        Map<String, Object> latestItemData =
            asMap(latestItem.get('item_data'));
        
        Map<String, Object> outgoingItemData =
            asMap(outgoingObject.get('item_data'));
        
        if (latestItemData == null || outgoingItemData == null) {
            return;
        }
        
        List<Object> latestVariations =
            asList(latestItemData.get('variations'));
        
        List<Object> outgoingVariations =
            asList(outgoingItemData.get('variations'));
        
        if (
            latestVariations == null ||
            outgoingVariations == null
        ) {
            return;
        }
        
        Map<String, Map<String, Object>> latestById =
            new Map<String, Map<String, Object>>();
        
        for (Object rawLatestVariation : latestVariations) {
            Map<String, Object> latestVariation =
                asMap(rawLatestVariation);
            
            if (
                latestVariation == null ||
                latestVariation.get('id') == null
            ) {
                continue;
            }
            
            latestById.put(
                String.valueOf(latestVariation.get('id')),
                latestVariation
            );
        }
        
        for (Object rawOutgoingVariation : outgoingVariations) {
            Map<String, Object> outgoingVariation =
                asMap(rawOutgoingVariation);
            
            if (
                outgoingVariation == null ||
                outgoingVariation.get('id') == null
            ) {
                continue;
            }
            
            String variationId =
                String.valueOf(outgoingVariation.get('id'));
            
            if (
                String.isBlank(variationId) ||
                variationId.startsWith('#') ||
                !latestById.containsKey(variationId)
            ) {
                continue;
            }
            
            copyVersion(
                latestById.get(variationId),
                outgoingVariation
            );
        }
    }
    
    private static void copyVersion(
        Map<String, Object> source,
        Map<String, Object> target
    ) {
        if (
            source != null &&
            target != null &&
            source.get('version') != null
        ) {
            target.put('version', source.get('version'));
        }
    }
    
    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object>
            ? (Map<String, Object>) value
            : null;
    }
    
    private static List<Object> asList(Object value) {
        return value instanceof List<Object>
            ? (List<Object>) value
            : null;
    }
    
    private static Map<String, Object> parseResponse(
        HttpResponse response
    ) {
        return (Map<String, Object>)
            JSON.deserializeUntyped(response.getBody());
    }
    
    public static String createImageObject(String imageUrl) {
        Map<String, Object> imageData = new Map<String, Object>{
            'name' => 'Product Image',
                'url'  => imageUrl
                };
                    Map<String, Object> catalogObject = new Map<String, Object>{
                        'type'       => 'IMAGE',
                            'id'         => '#IMG_' + String.valueOf(Crypto.getRandomLong()),
                            'image_data' => imageData
                            };
                                Map<String, Object> response = upsertCatalogObject(catalogObject);
        Map<String, Object> obj = (Map<String, Object>) response.get('catalog_object');
        return obj == null ? null : String.valueOf(obj.get('id'));
    }
    
    public static Map<String, Object> createCatalogImage(
        String squareItemId,
        String imageName,
        Blob imageBlob,
        String fileName,
        String mimeType
    ) {
        if (String.isBlank(squareItemId)) {
            throw new CalloutException('Square catalog image upload failed: squareItemId is blank.');
        }
        
        if (imageBlob == null || imageBlob.size() == 0) {
            throw new CalloutException('Square catalog image upload failed: imageBlob is blank.');
        }
        
        if (String.isBlank(imageName)) {
            imageName = 'Product Image';
        }
        
        if (String.isBlank(fileName)) {
            fileName = 'square-product-image.jpg';
        }
        
        if (String.isBlank(mimeType)) {
            mimeType = 'image/jpeg';
        }
        
        String safeFileName = fileName.replace('"', '');
        String safeImageName = imageName.replace('"', '');
        
        String boundary =
            'SalesforceBoundary' +
            String.valueOf(Math.abs(Crypto.getRandomInteger())) +
            String.valueOf(Datetime.now().getTime());
        
        Map<String, Object> requestMap = new Map<String, Object>{
            'idempotency_key' =>
                String.valueOf(Math.abs(Crypto.getRandomLong())) +
                '-' +
                String.valueOf(Datetime.now().getTime()),
                'object_id' => squareItemId,
                'image' => new Map<String, Object>{
                    'id' => '#IMG_' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                        'type' => 'IMAGE',
                        'image_data' => new Map<String, Object>{
                            'name' => safeImageName
                                }
                },
                    'is_primary' => true
                    };
                        
                        String requestJson = JSON.serialize(requestMap);
        
        /*
* Square official multipart shape:
* - file
* - request
*
* Keep file first, then request, matching Square's cURL example.
*/
        String header =
            '--' + boundary + '\r\n' +
            'Content-Disposition: form-data; name="file"; filename="' + safeFileName + '"\r\n' +
            'Content-Type: ' + mimeType + '\r\n\r\n';
        
        String footer =
            '\r\n--' + boundary + '\r\n' +
            'Content-Disposition: form-data; name="request"\r\n' +
            'Content-Type: application/json\r\n\r\n' +
            requestJson + '\r\n' +
            '--' + boundary + '--\r\n';
        
        Blob multipartBody = buildMultipartBody(header, imageBlob, footer);
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_API/v2/catalog/images');
        req.setMethod('POST');
        req.setTimeout(120000);
        
        req.setHeader('Square-Version', '2026-01-22');
        req.setHeader('Accept', 'application/json');
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        
        req.setBodyAsBlob(multipartBody);
        
        System.debug(
            LoggingLevel.INFO,
            'Square catalog image upload request prepared. ' +
            'squareItemId=' + squareItemId +
            ', imageName=' + safeImageName +
            ', fileName=' + safeFileName +
            ', mimeType=' + mimeType +
            ', imageBlobSize=' + imageBlob.size() +
            ', multipartBodySize=' + multipartBody.size() +
            ', boundary=' + boundary +
            ', multipartShape=file-request'
        );
        
        HttpResponse res = new Http().send(req);
        
        System.debug(
            LoggingLevel.INFO,
            'Square catalog image upload response. ' +
            'StatusCode=' + res.getStatusCode() +
            ', Status=' + res.getStatus() +
            ', Body=' + res.getBody()
        );
        
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Square catalog image upload failed. Status=' +
                res.getStatusCode() +
                ', Body=' +
                res.getBody()
            );
        }
        
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }
    private static Blob buildMultipartBody(
        String header,
        Blob fileBlob,
        String footer
    ) {
        String headerHex = EncodingUtil.convertToHex(Blob.valueOf(header));
        String fileHex = EncodingUtil.convertToHex(fileBlob);
        String footerHex = EncodingUtil.convertToHex(Blob.valueOf(footer));
        
        return EncodingUtil.convertFromHex(headerHex + fileHex + footerHex);
    }
    
    // CHANGE: Token updated from EAAAlz... to EAAAl4... to match retrieveSquareOrder.
    // The old token was returning 401, causing SquarePaymentQueueable to skip
    // the Square order fetch and then fail with "uncommitted work pending" later.
    public static Map<String, Object> retrieveOrder(String orderId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_API/v2/orders/' +
                        EncodingUtil.urlEncode(orderId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Square-Version', '2026-01-22');
        req.setHeader('Content-Type', 'application/json');
        //req.setHeader('Authorization', 'Bearer EAAAl4spqzyO-LBuenGf3L7SSavvYW2xzF0-X4UpIseUgt6A4EndMcn55dqyiiMX');
        
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Square order retrieve failed. Status=' + res.getStatusCode() +
                ', Body=' + res.getBody()
            );
        }
        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (Map<String, Object>) root.get('order');
    }
    
    public static Map<String, Object> searchCatalogItemVariations() {
        List<Object> allObjects = new List<Object>();
        String cursor;
        
        do {
            String endpoint = 'callout:Square_API/v2/catalog/list?types=ITEM_VARIATION';
            if (!String.isBlank(cursor)) {
                endpoint += '&cursor=' + EncodingUtil.urlEncode(cursor, 'UTF-8');
            }
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Square-Version', '2026-01-22');
            req.setHeader('Content-Type', 'application/json');
            //req.setHeader('Authorization', 'Bearer EAAAl4spqzyO-LBuenGf3L7SSavvYW2xzF0-X4UpIseUgt6A4EndMcn55dqyiiMX');
            
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                throw new CalloutException(
                    'Square catalog list failed. Status=' + res.getStatusCode() +
                    ', Body=' + res.getBody()
                );
            }
            
            Map<String, Object> page =
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            
            if (page.containsKey('objects') && page.get('objects') != null) {
                allObjects.addAll((List<Object>) page.get('objects'));
            }
            cursor = page.containsKey('cursor') ? (String) page.get('cursor') : null;
            
        } while (!String.isBlank(cursor));
        
        return new Map<String, Object>{ 'objects' => allObjects };
            }
    
    public static Map<String, Object> retrieveCatalogObject(String objectId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_API/v2/catalog/object/' +
                        EncodingUtil.urlEncode(objectId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Square-Version', '2026-01-22');
        req.setHeader('Content-Type', 'application/json');
        //req.setHeader('Authorization', 'Bearer EAAAl4spqzyO-LBuenGf3L7SSavvYW2xzF0-X4UpIseUgt6A4EndMcn55dqyiiMX');
        
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Square catalog object retrieve failed. Status=' + res.getStatusCode() +
                ', Body=' + res.getBody()
            );
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }
    
    public static Map<String, Object> retrieveCustomer(String customerId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_API/v2/customers/' +
                        EncodingUtil.urlEncode(customerId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Square-Version', '2026-01-22');
        req.setHeader('Content-Type', 'application/json');
        //req.setHeader('Authorization', 'Bearer EAAAl4spqzyO-LBuenGf3L7SSavvYW2xzF0-X4UpIseUgt6A4EndMcn55dqyiiMX');
        
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Square customer retrieve failed. Status=' + res.getStatusCode() +
                ', Body=' + res.getBody()
            );
        }
        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (Map<String, Object>) root.get('customer');
    }
    
    public static Map<String, Object> retrieveSquareOrder(String orderId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_API/v2/orders/' +
                        EncodingUtil.urlEncode(orderId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Square-Version', '2026-01-22');
        req.setHeader('Content-Type', 'application/json');
        //req.setHeader('Authorization', 'Bearer EAAAl4spqzyO-LBuenGf3L7SSavvYW2xzF0-X4UpIseUgt6A4EndMcn55dqyiiMX');
        
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Square order retrieve failed. Status=' + res.getStatusCode() +
                ', Body=' + res.getBody()
            );
        }
        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (Map<String, Object>) root.get('order');
    }
    
    /** Retrieves one Square Location by the location_id already stored on Order. */
    public static Map<String, Object> retrieveSquareLocation(String squareLocationId) {
        if (String.isBlank(squareLocationId)) {
            return null;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_API/v2/locations/' +
            EncodingUtil.urlEncode(squareLocationId, 'UTF-8'));
        req.setMethod('GET');
        req.setTimeout(120000);
        req.setHeader('Square-Version', '2026-01-22');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');

        HttpResponse res = new Http().send(req);
        System.debug(LoggingLevel.INFO,
            'SquareApiClient.retrieveSquareLocation response. locationId=' + squareLocationId +
            ', statusCode=' + res.getStatusCode() + ', body=' + res.getBody());

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Square location retrieve failed. Status=' + res.getStatusCode() +
                ', Body=' + res.getBody()
            );
        }

        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (Map<String, Object>) root.get('location');
    }

    public static Map<String, Object> retrieveRefund(String refundId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_API/v2/refunds/' +
                        EncodingUtil.urlEncode(refundId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Square-Version', '2026-01-22');
        req.setHeader('Content-Type', 'application/json');
        //req.setHeader('Authorization', 'Bearer EAAAl4spqzyO-LBuenGf3L7SSavvYW2xzF0-X4UpIseUgt6A4EndMcn55dqyiiMX');
        
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Square refund retrieve failed. Status=' + res.getStatusCode() +
                ', Body=' + res.getBody()
            );
        }
        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (Map<String, Object>) root.get('refund');
    }
    
    public static Map<String, Object> createSquareLocation(
        String locationName,
        Boolean isActive
    ) {
        if (String.isBlank(locationName)) {
            throw new CalloutException('Square location create failed: locationName is blank.');
        }
        
        /*
* Important:
* For CreateLocation, send the minimum required payload.
* Square can derive remaining fields from the main location.
* Do not send status on create.
*/
        Map<String, Object> locationMap = new Map<String, Object>{
            'name' => locationName,
                'type' => 'PHYSICAL'
                };
                    
                    Map<String, Object> requestMap = new Map<String, Object>{
                        'location' => locationMap
                            };
                                
                                HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_API/v2/locations');
        req.setMethod('POST');
        req.setTimeout(120000);
        req.setHeader('Square-Version', '2026-01-22');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setBody(JSON.serialize(requestMap));
        
        System.debug(
            LoggingLevel.INFO,
            'SquareApiClient.createSquareLocation request=' +
            JSON.serialize(requestMap)
        );
        
        HttpResponse res = new Http().send(req);
        
        System.debug(
            LoggingLevel.INFO,
            'SquareApiClient.createSquareLocation response. StatusCode=' +
            res.getStatusCode() +
            ', Body=' +
            res.getBody()
        );
        
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Square location create failed. Status=' +
                res.getStatusCode() +
                ', Body=' +
                res.getBody()
            );
        }
        
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }
    
    public static Map<String, Object> updateSquareLocation(
        String squareLocationId,
        String locationName,
        Boolean isActive
    ) {
        if (String.isBlank(squareLocationId)) {
            throw new CalloutException('Square location update failed: squareLocationId is blank.');
        }
        
        if (String.isBlank(locationName)) {
            throw new CalloutException('Square location update failed: locationName is blank.');
        }
        
        Map<String, Object> locationMap = new Map<String, Object>{
            'name' => locationName,
                'type' => 'PHYSICAL'
                };
                    
                    if (isActive != null) {
                        locationMap.put('status', isActive ? 'ACTIVE' : 'INACTIVE');
                    }
        
        Map<String, Object> requestMap = new Map<String, Object>{
            'location' => locationMap
                };
                    
                    HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_API/v2/locations/' + EncodingUtil.urlEncode(squareLocationId, 'UTF-8'));
        req.setMethod('PUT');
        req.setTimeout(120000);
        req.setHeader('Square-Version', '2026-01-22');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setBody(JSON.serialize(requestMap));
        
        System.debug(
            LoggingLevel.INFO,
            'SquareApiClient.updateSquareLocation request. squareLocationId=' +
            squareLocationId +
            ', body=' +
            JSON.serialize(requestMap)
        );
        
        HttpResponse res = new Http().send(req);
        
        System.debug(
            LoggingLevel.INFO,
            'SquareApiClient.updateSquareLocation response. StatusCode=' +
            res.getStatusCode() +
            ', Body=' +
            res.getBody()
        );
        
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Square location update failed. Status=' +
                res.getStatusCode() +
                ', Body=' +
                res.getBody()
            );
        }
        
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }
    
    public static List<Object> listSquareLocations() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_API/v2/locations');
        req.setMethod('GET');
        req.setTimeout(120000);
        req.setHeader('Square-Version', '2026-01-22');
        req.setHeader('Accept', 'application/json');
        
        HttpResponse res = new Http().send(req);
        
        System.debug(
            LoggingLevel.INFO,
            'SquareApiClient.listSquareLocations response. StatusCode=' +
            res.getStatusCode() +
            ', Body=' +
            res.getBody()
        );
        
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Square list locations failed. Status=' +
                res.getStatusCode() +
                ', Body=' +
                res.getBody()
            );
        }
        
        Map<String, Object> responseMap =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        
        Object locationsObj = responseMap.get('locations');
        
        if (locationsObj == null) {
            return new List<Object>();
        }
        
        return (List<Object>) locationsObj;
    }
    
    @TestVisible
    private static HttpResponse sendCatalogUpsertRequest(Map<String, Object> catalogObject) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Square_API/v2/catalog/object');
        req.setMethod('POST');
        req.setHeader('Square-Version', '2026-01-22');
        req.setHeader('Content-Type', 'application/json');
        //req.setHeader('Authorization', 'Bearer EAAAl4spqzyO-LBuenGf3L7SSavvYW2xzF0-X4UpIseUgt6A4EndMcn55dqyiiMX');
        
        Map<String, Object> body = new Map<String, Object>{
            'idempotency_key' => String.valueOf(Crypto.getRandomLong()) + '-' +
                String.valueOf(System.now().getTime()),
                'object' => catalogObject
                };
                    
                    req.setBody(JSON.serialize(body));
        
        return new Http().send(req);
    }
    
    @TestVisible
    private static Boolean isSquareVersionMismatch(HttpResponse res) {
        if (res == null || String.isBlank(res.getBody())) {
            return false;
        }
        
        return res.getStatusCode() == 400 &&
            res.getBody().contains('VERSION_MISMATCH');
    }
}