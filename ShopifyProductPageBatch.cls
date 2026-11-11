public without sharing class ShopifyProductPageBatch
implements Database.Batchable<String>,
           Database.AllowsCallouts,
           Database.Stateful {

    private static final String NAMED_CREDENTIAL =
        'callout:Shopify_Admin_API';

    private static final String API_VERSION =
        '2026-04';

    private static final Integer PAGE_SIZE = 25;

    /*
     * Cursor used for GraphQL product pagination.
     *
     * null = first page
     */
    private String afterCursor;

    /*
     * Set by start() and used by finish().
     */
    private Boolean hasNextPage = false;
    private String nextCursor;


    public ShopifyProductPageBatch() {
        this(null);
    }


    public ShopifyProductPageBatch(
        String afterCursor
    ) {
        this.afterCursor = afterCursor;
    }


    /*
     * ========================================================
     * START
     * ========================================================
     *
     * Fetch one GraphQL page of Shopify product IDs.
     *
     * The batch work item is ONLY the Shopify product ID.
     * Actual REST product retrieval happens in execute(), where
     * batch scope = 1 gives each product its own transaction.
     * ========================================================
     */
    public Iterable<String> start(
        Database.BatchableContext context
    ) {

        List<String> productIds =
            new List<String>();


        HttpResponse response =
            sendGraphQlRequest(
                afterCursor
            );


        Map<String, Object> root =
            deserializeResponse(
                response
            );


        /*
         * ====================================================
         * Validate GraphQL response
         * ====================================================
         */

        List<Object> errors =
            getObjectList(
                root,
                'errors'
            );


        if (!errors.isEmpty()) {

            throw new ShopifyProductPageBatchException(
                'Shopify GraphQL product query returned errors: '
                + JSON.serialize(errors)
            );
        }


        Map<String, Object> data =
            castToMap(
                root.get('data')
            );


        if (data == null) {

            throw new ShopifyProductPageBatchException(
                'Shopify GraphQL product query returned no data. '
                + 'Response='
                + response.getBody()
            );
        }


        Map<String, Object> productsConnection =
            castToMap(
                data.get('products')
            );


        if (productsConnection == null) {

            throw new ShopifyProductPageBatchException(
                'Shopify GraphQL response did not contain products. '
                + 'Response='
                + response.getBody()
            );
        }


        /*
         * ====================================================
         * Read nodes
         * ====================================================
         */

        List<Object> nodes =
            getObjectList(
                productsConnection,
                'nodes'
            );


        for (Object nodeObject : nodes) {

            Map<String, Object> node =
                castToMap(
                    nodeObject
                );


            if (node == null) {
                continue;
            }


            String legacyProductId =
                normalizeId(
                    node.get(
                        'legacyResourceId'
                    )
                );


            if (
                !String.isBlank(
                    legacyProductId
                )
            ) {

                productIds.add(
                    legacyProductId
                );
            }
        }


        /*
         * ====================================================
         * Read pagination state
         * ====================================================
         */

        Map<String, Object> pageInfo =
            castToMap(
                productsConnection.get(
                    'pageInfo'
                )
            );


        hasNextPage = false;
        nextCursor = null;


        if (pageInfo != null) {

            Object hasNextRaw =
                pageInfo.get(
                    'hasNextPage'
                );


            if (hasNextRaw != null) {

                hasNextPage =
                    Boolean.valueOf(
                        String.valueOf(
                            hasNextRaw
                        )
                    );
            }


            if (
                pageInfo.get(
                    'endCursor'
                ) != null
            ) {

                nextCursor =
                    String.valueOf(
                        pageInfo.get(
                            'endCursor'
                        )
                    );
            }
        }


        System.debug(
            LoggingLevel.ERROR,
            'SHOPIFY PRODUCT GRAPHQL PAGE'
            + ' | AFTER_CURSOR='
                + afterCursor
            + ' | PRODUCT_COUNT='
                + productIds.size()
            + ' | HAS_NEXT_PAGE='
                + hasNextPage
            + ' | NEXT_CURSOR='
                + nextCursor
        );


        return productIds;
    }


    /*
     * ========================================================
     * EXECUTE
     * ========================================================
     *
     * Scope MUST remain 1.
     *
     * For each Shopify product ID:
     *
     * 1. Fetch complete REST product payload.
     * 2. Pass that payload into existing ProductOrchestrationService.
     *
     * This means we preserve all your existing:
     *
     * - Parent logic
     * - Variant logic
     * - Material logic
     * - Size logic
     * - Weight logic
     * - Inventory_Item_Id__c mapping
     * - SKU logic
     * - Standard PricebookEntry
     * - Square PricebookEntry
     * - Product image logic
     *
     * ========================================================
     */
    public void execute(
        Database.BatchableContext context,
        List<String> scope
    ) {

        if (
            scope == null ||
            scope.isEmpty()
        ) {
            return;
        }


        String shopifyProductId =
            scope[0];


        if (
            String.isBlank(
                shopifyProductId
            )
        ) {
            return;
        }


        Map<String, Object> productPayload =
            fetchRestProduct(
                shopifyProductId
            );


        if (productPayload == null) {

            System.debug(
                LoggingLevel.ERROR,
                'SHOPIFY PRODUCT SKIPPED'
                + ' | SHOPIFY_PRODUCT_ID='
                    + shopifyProductId
                + ' | REASON=REST_PRODUCT_PAYLOAD_NULL'
            );

            return;
        }


        ProductOrchestrationService.processProductsFromRestRequest(
                new Map<String, Object>{
                    'product' =>
                        productPayload
                },
                new String[]{
                    'products',
                    'variants'
                }
            );


        System.debug(
            LoggingLevel.INFO,
            'SHOPIFY PRODUCT PROCESSED'
            + ' | SHOPIFY_PRODUCT_ID='
                + shopifyProductId
        );
    }


    /*
     * ========================================================
     * FINISH
     * ========================================================
     *
     * Chain the next GraphQL page.
     * ========================================================
     */
    public void finish(
        Database.BatchableContext context
    ) {

        if (
            !hasNextPage ||
            String.isBlank(
                nextCursor
            )
        ) {

            System.debug(
                LoggingLevel.ERROR,
                'SHOPIFY PRODUCT BACKFILL COMPLETED'
            );

            return;
        }


        System.debug(
            LoggingLevel.INFO,
            'SHOPIFY PRODUCT BACKFILL CONTINUING'
            + ' | NEXT_CURSOR='
                + nextCursor
        );


        Database.executeBatch(
            new ShopifyProductPageBatch(
                nextCursor
            ),
            1
        );
    }


    /*
     * ========================================================
     * GRAPHQL PRODUCT PAGE
     * ========================================================
     */
    private static HttpResponse sendGraphQlRequest(
        String cursor
    ) {

        String query =
            'query ProductBackfill($first: Int!, $after: String) {'
            + ' products(first: $first, after: $after) {'
            + '   nodes {'
            + '     id'
            + '     legacyResourceId'
            + '   }'
            + '   pageInfo {'
            + '     hasNextPage'
            + '     endCursor'
            + '   }'
            + ' }'
            + '}';


        Map<String, Object> variables =
            new Map<String, Object>{
                'first' => PAGE_SIZE,
                'after' => cursor
            };


        Map<String, Object> requestBody =
            new Map<String, Object>{
                'query' => query,
                'variables' => variables
            };


        HttpRequest request =
            new HttpRequest();


        request.setMethod(
            'POST'
        );


        request.setEndpoint(
            NAMED_CREDENTIAL
            + '/admin/api/'
            + API_VERSION
            + '/graphql.json'
        );


        request.setHeader(
            'Content-Type',
            'application/json'
        );


        request.setHeader(
            'Accept',
            'application/json'
        );


        request.setTimeout(
            120000
        );


        request.setBody(
            JSON.serialize(
                requestBody
            )
        );


        HttpResponse response =
            new Http().send(
                request
            );


        validateHttpResponse(
            response,
            'GraphQL product page'
        );


        return response;
    }


    /*
     * ========================================================
     * REST PRODUCT FETCH
     * ========================================================
     *
     * Existing ProductOrchestrationService already expects
     * REST-shaped Shopify JSON, so retrieve the complete
     * product using its legacy Shopify product ID.
     * ========================================================
     */
    private static Map<String, Object> fetchRestProduct(
        String shopifyProductId
    ) {

        String requestEndpoint =
            NAMED_CREDENTIAL
            + '/admin/api/'
            + API_VERSION
            + '/products/'
            + EncodingUtil.urlEncode(
                shopifyProductId,
                'UTF-8'
            )
            + '.json';


        HttpRequest request =
            new HttpRequest();


        request.setMethod(
            'GET'
        );


        request.setEndpoint(
            requestEndpoint
        );


        request.setHeader(
            'Accept',
            'application/json'
        );


        request.setTimeout(
            120000
        );


        HttpResponse response =
            new Http().send(
                request
            );


        validateHttpResponse(
            response,
            'REST product fetch '
            + shopifyProductId
        );


        Map<String, Object> root =
            deserializeResponse(
                response
            );


        return castToMap(
            root.get(
                'product'
            )
        );
    }


    /*
     * ========================================================
     * HTTP VALIDATION
     * ========================================================
     */
    private static void validateHttpResponse(
        HttpResponse response,
        String operation
    ) {

        if (response == null) {

            throw new ShopifyProductPageBatchException(
                operation
                + ' returned a null HTTP response.'
            );
        }


        Integer statusCode =
            response.getStatusCode();


        if (
            statusCode < 200 ||
            statusCode >= 300
        ) {

            throw new ShopifyProductPageBatchException(
                operation
                + ' failed.'
                + ' Status='
                + statusCode
                + ', Body='
                + response.getBody()
            );
        }
    }


    /*
     * ========================================================
     * JSON HELPERS
     * ========================================================
     */
    private static Map<String, Object> deserializeResponse(
        HttpResponse response
    ) {

        if (response == null) {

            throw new ShopifyProductPageBatchException(
                'Shopify returned a null HTTP response.'
            );
        }


        if (
            String.isBlank(
                response.getBody()
            )
        ) {

            return new Map<String, Object>();
        }


        Map<String, Object> result =
            castToMap(
                JSON.deserializeUntyped(
                    response.getBody()
                )
            );


        if (result == null) {

            throw new ShopifyProductPageBatchException(
                'Unexpected Shopify response: '
                + response.getBody()
            );
        }


        return result;
    }


    private static List<Object> getObjectList(
        Map<String, Object> payload,
        String propertyName
    ) {

        if (
            payload == null ||
            String.isBlank(
                propertyName
            ) ||
            !payload.containsKey(
                propertyName
            )
        ) {

            return new List<Object>();
        }


        try {

            return (List<Object>)
                payload.get(
                    propertyName
                );

        } catch (Exception e) {

            return new List<Object>();
        }
    }


    private static Map<String, Object> castToMap(
        Object rawValue
    ) {

        if (rawValue == null) {
            return null;
        }


        try {

            return (Map<String, Object>)
                rawValue;

        } catch (Exception e) {

            return null;
        }
    }


    /*
     * ========================================================
     * ID NORMALIZATION
     * ========================================================
     *
     * GraphQL legacyResourceId normally arrives as a number.
     * This safely turns it into the REST Shopify ID string.
     * ========================================================
     */
    private static String normalizeId(
        Object rawValue
    ) {

        if (rawValue == null) {
            return null;
        }


        String value =
            String.valueOf(
                rawValue
            ).trim();


        if (
            String.isBlank(
                value
            )
        ) {
            return null;
        }


        /*
         * Handle Decimal-style values if deserializeUntyped()
         * gives us a numeric representation.
         */
        if (
            value.endsWith(
                '.0'
            )
        ) {

            value =
                value.substring(
                    0,
                    value.length() - 2
                );
        }


        return value;
    }


    public class ShopifyProductPageBatchException
        extends Exception {
    }
}