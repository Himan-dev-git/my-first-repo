public without sharing class SquareSalesAssistantOrderQueueable implements Queueable {
    
    private static final String MODE_CREATE_USER = 'CREATE_USER';
    private static final String MODE_SYNC_ORDER = 'SYNC_ORDER';

    private String mode;
    private String teamMemberId;
    private String paymentId;
    private String paymentJson;
    private String squareOrderJson; 

    public SquareSalesAssistantOrderQueueable(
        String mode,
        String teamMemberId,
        String paymentId,
        String paymentJson,
        String squareOrderJson
    ) {
        this.mode = mode;
        this.teamMemberId = teamMemberId;
        this.paymentId = paymentId;
        this.paymentJson = paymentJson;
        this.squareOrderJson = squareOrderJson;
    }

    public void execute(QueueableContext context) {
        if (mode == MODE_CREATE_USER) {
            createUserIfMissing();

            System.enqueueJob(
                new SquareSalesAssistantOrderQueueable(
                    MODE_SYNC_ORDER,
                    teamMemberId,
                    paymentId,
                    paymentJson,
                    squareOrderJson
                )
            );

            return;
        }

        if (mode == MODE_SYNC_ORDER) {
            Map<String, Object> payment =
                (Map<String, Object>) JSON.deserializeUntyped(paymentJson);

            Map<String, Object> squareOrder;

            if (!String.isBlank(squareOrderJson)) {
                squareOrder =
                    (Map<String, Object>) JSON.deserializeUntyped(squareOrderJson);
            }

            SquareOrderSyncService.syncPaymentToOrder(
                paymentId,
                payment,
                squareOrder
            );
        }
    }

    private void createUserIfMissing() {
        if (String.isBlank(teamMemberId)) {
            return;
        }

        List<User> existingUsers = [
            SELECT Id
            FROM User
            WHERE Square_Team_Member_Id__c = :teamMemberId
            LIMIT 1
        ];

        if (!existingUsers.isEmpty()) {
            System.debug(
                LoggingLevel.INFO,
                'SquareSalesAssistantOrderQueueable: User already exists. userId=' +
                existingUsers[0].Id +
                ', teamMemberId=' +
                teamMemberId
            );

            return;
        }

        Map<String, Object> payment =
            (Map<String, Object>) JSON.deserializeUntyped(paymentJson);

        String fullName = extractSalesAssistantName(payment);

        if (String.isBlank(fullName)) {
            fullName = 'Square Team Member ' + teamMemberId.right(6);
        }

        String firstName;
        String lastName;

        List<String> nameParts = fullName.trim().split('\\s+');

        if (nameParts.size() == 1) {
            lastName = nameParts[0];
        } else {
            firstName = nameParts[0];
            lastName = nameParts[nameParts.size() - 1];
        }

        Profile p = getFreeUserProfile();

        String uniqueSuffix =
            UserInfo.getOrganizationId().right(6) +
            String.valueOf(DateTime.now().getTime());

        User u = new User();
        u.ProfileId = p.Id;
        u.FirstName = firstName;
        u.LastName = String.isBlank(lastName) ? 'Square User' : lastName;

        u.Email =
            'square-team-' +
            teamMemberId.right(8).toLowerCase() +
            '-' +
            uniqueSuffix +
            '@example.invalid';

        u.Username =
            'square-team-' +
            teamMemberId.right(8).toLowerCase() +
            '-' +
            uniqueSuffix +
            '@example.invalid';

        u.Alias = buildUserAlias(firstName, lastName);

        u.CommunityNickname =
            'sq' +
            teamMemberId.right(6).toLowerCase() +
            uniqueSuffix.right(6);

        u.TimeZoneSidKey = 'Europe/London';
        u.LocaleSidKey = 'en_GB';
        u.EmailEncodingKey = 'UTF-8';
        u.LanguageLocaleKey = 'en_US';
        u.Square_Team_Member_Id__c = teamMemberId;
        u.IsActive = true;

        try {
            insert u;

            System.debug(
                LoggingLevel.INFO,
                'SquareSalesAssistantOrderQueueable: created User. userId=' +
                u.Id +
                ', teamMemberId=' +
                teamMemberId +
                ', name=' +
                fullName
            );

        } catch (DmlException e) {
            if (e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
                System.debug(
                    LoggingLevel.WARN,
                    'SquareSalesAssistantOrderQueueable: duplicate User detected. ' +
                    'Continuing to deferred Order sync. teamMemberId=' +
                    teamMemberId
                );
            } else {
                throw e;
            }
        }
    }

    private static String extractSalesAssistantName(
        Map<String, Object> payment
    ) {
        if (payment == null) {
            return null;
        }

        if (payment.get('team_member_name') != null) {
            return String.valueOf(payment.get('team_member_name'));
        }

        if (payment.get('employee_name') != null) {
            return String.valueOf(payment.get('employee_name'));
        }

        if (payment.get('creator_name') != null) {
            return String.valueOf(payment.get('creator_name'));
        }

        return null;
    }

    private static Profile getFreeUserProfile() {
        List<Profile> profiles = [
            SELECT Id, Name, UserLicense.Name
            FROM Profile
            WHERE UserLicense.Name IN ('Chatter Free', 'Identity')
            ORDER BY UserLicense.Name
            LIMIT 1
        ];

        if (profiles.isEmpty()) {
            throw new SquareSalesAssistantUserException(
                'No free User profile found. Expected Chatter Free or Identity profile.'
            );
        }

        return profiles[0];
    }

    private static String buildUserAlias(
        String firstName,
        String lastName
    ) {
        String source = '';

        if (!String.isBlank(firstName)) {
            source += firstName.left(1);
        }

        if (!String.isBlank(lastName)) {
            source += lastName;
        }

        if (String.isBlank(source)) {
            source = 'squser';
        }

        source = source.replaceAll('[^A-Za-z0-9]', '').toLowerCase();

        if (source.length() > 8) {
            source = source.left(8);
        }

        return source;
    }

    public class SquareSalesAssistantUserException extends Exception {}
}