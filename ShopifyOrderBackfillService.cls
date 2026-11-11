public without sharing class ShopifyOrderBackfillService {

    private static final String NAMED_CREDENTIAL =
        'callout:Shopify_Admin_API';

    private static final String API_VERSION =
        '2026-04';

    /*
     * One order per Queueable transaction is deliberate.
     * The existing Order automation consumes a high number of SOQL queries.
     * Processing one order at a time gives every order a fresh governor-limit
     * transaction while still allowing the entire migration to be started
     * with one Execute Anonymous command.
     */
    private static final Integer ORDERS_PER_JOB = 1;

    private static final String GRAPHQL_ENDPOINT =
        NAMED_CREDENTIAL +
        '/admin/api/' +
        API_VERSION +
        '/graphql.json';

    /*
     * Starts a migration for every order that the production Shopify token
     * is authorized to read.
     */
    public static Id backfillAllOrders() {
        return System.enqueueJob(
            new OrderPageQueueable(
                null,
                null
            )
        );
    }

    /*
     * Starts a migration from a given Shopify created-at date.
     */
    public static Id backfillOrdersFrom(
        Datetime createdAtMin
    ) {
        if (createdAtMin == null) {
            return backfillAllOrders();
        }

        String queryFilter =
            'created_at:>=' +
            formatShopifySearchDatetime(createdAtMin);

        return System.enqueueJob(
            new OrderPageQueueable(
                null,
                queryFilter
            )
        );
    }

    /*
     * Starts a migration for a controlled Shopify created-at range.
     */
    public static Id backfillOrdersBetween(
        Datetime createdAtMin,
        Datetime createdAtMax
    ) {
        if (
            createdAtMin == null ||
            createdAtMax == null
        ) {
            throw new ShopifyOrderBackfillException(
                'Both createdAtMin and createdAtMax are required.'
            );
        }

        if (createdAtMax <= createdAtMin) {
            throw new ShopifyOrderBackfillException(
                'createdAtMax must be later than createdAtMin.'
            );
        }

        String queryFilter =
            'created_at:>=' +
            formatShopifySearchDatetime(createdAtMin) +
            ' created_at:<=' +
            formatShopifySearchDatetime(createdAtMax);

        return System.enqueueJob(
            new OrderPageQueueable(
                null,
                queryFilter
            )
        );
    }

    public class OrderPageQueueable
    implements Queueable, Database.AllowsCallouts {

        private String afterCursor;
        private String queryFilter;

        public OrderPageQueueable(
            String afterCursor,
            String queryFilter
        ) {
            this.afterCursor = afterCursor;
            this.queryFilter = queryFilter;
        }

        public void execute(
            QueueableContext context
        ) {
            OrderPageResult page;

            try {
                page = fetchOrderPage(
                    afterCursor,
                    queryFilter
                );
            } catch (Exception pageException) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Shopify order migration could not retrieve the next ' +
                    'GraphQL page. Cursor=' + afterCursor +
                    ', Filter=' + queryFilter +
                    ', Error=' + pageException.getMessage() +
                    ', StackTrace=' +
                    pageException.getStackTraceString()
                );

                return;
            }

            for (String shopifyOrderId : page.orderIds) {
                try {
                    Map<String, Object> orderPayload =
                        fetchRestOrder(shopifyOrderId);

                    if (orderPayload == null) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'Shopify order migration returned no order body. ' +
                            'ShopifyOrderId=' + shopifyOrderId
                        );

                        continue;
                    }

                    /*
                     * This is exactly the same singular payload path that
                     * succeeded in Execute Anonymous for the old order.
                     */
                    OrderOrchestrationService.processOrdersFromRestRequest(
                        new Map<String, Object>{
                            'order' => orderPayload
                        },
                        new String[]{
                            'orders',
                            'order_items',
                            'fulfillments'
                        }
                    );

                    System.debug(
                        LoggingLevel.INFO,
                        'Shopify historical order processed successfully. ' +
                        'ShopifyOrderId=' + shopifyOrderId
                    );
                } catch (Exception orderException) {
                    /*
                     * A normal exception on one order must not prevent the
                     * cursor chain from continuing to the next order.
                     */
                    System.debug(
                        LoggingLevel.ERROR,
                        'Shopify historical order failed. ' +
                        'ShopifyOrderId=' + shopifyOrderId +
                        ', Error=' + orderException.getMessage() +
                        ', StackTrace=' +
                        orderException.getStackTraceString()
                    );
                }
            }

            if (
                page.hasNextPage == true &&
                !String.isBlank(page.endCursor)
            ) {
                System.enqueueJob(
                    new OrderPageQueueable(
                        page.endCursor,
                        queryFilter
                    )
                );
            } else {
                System.debug(
                    LoggingLevel.INFO,
                    'Shopify order migration completed. ' +
                    'FinalCursor=' + page.endCursor +
                    ', Filter=' + queryFilter
                );
            }
        }
    }

    private class OrderPageResult {
        public List<String> orderIds =
            new List<String>();

        public Boolean hasNextPage = false;
        public String endCursor;
    }

    @TestVisible
    private static OrderPageResult fetchOrderPage(
        String afterCursor,
        String queryFilter
    ) {
        String graphQlQuery =
            'query OrderBackfillPage(' +
            '$first: Int!, ' +
            '$after: String, ' +
            '$query: String' +
            ') {' +
            ' orders(' +
            'first: $first, ' +
            'after: $after, ' +
            'sortKey: CREATED_AT, ' +
            'reverse: false, ' +
            'query: $query' +
            ') {' +
            ' edges {' +
            ' cursor' +
            ' node {' +
            ' legacyResourceId' +
            ' }' +
            ' }' +
            ' pageInfo {' +
            ' hasNextPage' +
            ' endCursor' +
            ' }' +
            ' }' +
            '}';

        Map<String, Object> variables =
            new Map<String, Object>{
                'first' => ORDERS_PER_JOB,
                'after' => afterCursor,
                'query' => queryFilter
            };

        HttpRequest request = new HttpRequest();
        request.setMethod('POST');
        request.setEndpoint(GRAPHQL_ENDPOINT);
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
                new Map<String, Object>{
                    'query' => graphQlQuery,
                    'variables' => variables
                }
            )
        );

        HttpResponse response =
            new Http().send(request);

        validateResponse(
            response,
            'GraphQL order-page request'
        );

        Map<String, Object> body =
            castToMap(
                JSON.deserializeUntyped(
                    response.getBody()
                )
            );

        if (body == null) {
            throw new ShopifyOrderBackfillException(
                'Shopify GraphQL response was not a JSON object.'
            );
        }

        List<Object> graphQlErrors =
            getObjectList(body, 'errors');

        if (!graphQlErrors.isEmpty()) {
            throw new ShopifyOrderBackfillException(
                'Shopify GraphQL returned errors: ' +
                JSON.serialize(graphQlErrors)
            );
        }

        Map<String, Object> data =
            castToMap(body.get('data'));

        Map<String, Object> orders =
            data == null
                ? null
                : castToMap(data.get('orders'));

        if (orders == null) {
            throw new ShopifyOrderBackfillException(
                'Shopify GraphQL response did not contain data.orders. ' +
                'Body=' + response.getBody()
            );
        }

        OrderPageResult result =
            new OrderPageResult();

        for (Object rawEdge : getObjectList(orders, 'edges')) {
            Map<String, Object> edge =
                castToMap(rawEdge);

            Map<String, Object> node =
                edge == null
                    ? null
                    : castToMap(edge.get('node'));

            if (
                node == null ||
                node.get('legacyResourceId') == null
            ) {
                continue;
            }

            result.orderIds.add(
                String.valueOf(
                    node.get('legacyResourceId')
                )
            );
        }

        Map<String, Object> pageInfo =
            castToMap(orders.get('pageInfo'));

        if (pageInfo != null) {
            result.hasNextPage =
                pageInfo.get('hasNextPage') == true;

            result.endCursor =
                pageInfo.get('endCursor') == null
                    ? null
                    : String.valueOf(
                        pageInfo.get('endCursor')
                    );
        }

        System.debug(
            LoggingLevel.INFO,
            'Shopify GraphQL order page retrieved. ' +
            'InputCursor=' + afterCursor +
            ', OrderIds=' + result.orderIds +
            ', HasNextPage=' + result.hasNextPage +
            ', EndCursor=' + result.endCursor
        );

        return result;
    }

    @TestVisible
    private static Map<String, Object> fetchRestOrder(
        String shopifyOrderId
    ) {
        if (String.isBlank(shopifyOrderId)) {
            throw new ShopifyOrderBackfillException(
                'Shopify order ID is required.'
            );
        }

        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint(
            NAMED_CREDENTIAL +
            '/admin/api/' +
            API_VERSION +
            '/orders/' +
            EncodingUtil.urlEncode(
                shopifyOrderId,
                'UTF-8'
            ) +
            '.json'
        );
        request.setHeader(
            'Accept',
            'application/json'
        );
        request.setTimeout(120000);

        HttpResponse response =
            new Http().send(request);

        validateResponse(
            response,
            'REST order request for ' + shopifyOrderId
        );

        Map<String, Object> body =
            castToMap(
                JSON.deserializeUntyped(
                    response.getBody()
                )
            );

        Map<String, Object> orderPayload =
            body == null
                ? null
                : castToMap(body.get('order'));

        if (orderPayload == null) {
            throw new ShopifyOrderBackfillException(
                'Shopify REST response did not contain order. ' +
                'ShopifyOrderId=' + shopifyOrderId +
                ', Body=' + response.getBody()
            );
        }

        return orderPayload;
    }

    private static void validateResponse(
        HttpResponse response,
        String operation
    ) {
        if (response == null) {
            throw new ShopifyOrderBackfillException(
                operation + ' returned a null response.'
            );
        }

        Integer statusCode =
            response.getStatusCode();

        if (
            statusCode < 200 ||
            statusCode >= 300
        ) {
            throw new ShopifyOrderBackfillException(
                operation + ' failed. ' +
                'Status=' + statusCode +
                ', Body=' + response.getBody()
            );
        }
    }

    private static List<Object> getObjectList(
        Map<String, Object> source,
        String key
    ) {
        if (
            source == null ||
            String.isBlank(key) ||
            source.get(key) == null
        ) {
            return new List<Object>();
        }

        try {
            return (List<Object>) source.get(key);
        } catch (Exception castException) {
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
            return (Map<String, Object>) rawValue;
        } catch (Exception castException) {
            return null;
        }
    }

    private static String formatShopifySearchDatetime(
        Datetime value
    ) {
        return '\'' +
            value.formatGMT(
                'yyyy-MM-dd\'T\'HH:mm:ss\'Z\''
            ) +
            '\'';
    }

    public class ShopifyOrderBackfillException
    extends Exception {
    }
}