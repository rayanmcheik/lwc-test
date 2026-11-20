public with sharing class VGTSProductCatalogEmailAction {

    public class Request {
        @InvocableVariable(
            label='Destination'
            required=true
        )
        public String destination;

        @InvocableVariable(
            label='Customer Email'
            required=true
        )
        public String customerEmail;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Result Message')
        public String message;

        @InvocableVariable(label='Products Included')
        public Integer productsSent;
    }

    @InvocableMethod(
        label='Send VGTS Product Catalog Email'
        description='Searches active VGTS products and emails a branded HTML product catalog to a customer.'
    )
    public static List<Response> sendCatalog(
        List<Request> requests
    ) {
        List<Response> responses = new List<Response>();
        List<Messaging.SingleEmailMessage> emails =
            new List<Messaging.SingleEmailMessage>();

        List<Integer> responseIndexes = new List<Integer>();

        for (Request req : requests) {

            Response result = new Response();
            result.success = false;
            result.productsSent = 0;

            responses.add(result);

            if (req == null ||
                String.isBlank(req.destination) ||
                String.isBlank(req.customerEmail)) {

                result.message =
                    'Destination and customer email are required.';
                continue;
            }

            String recipient = req.customerEmail.trim();

            if (!Pattern.matches(
                '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$',
                recipient
            )) {
                result.message =
                    'The customer email address is invalid.';
                continue;
            }

            try {

                List<Product2> products = [
                    SELECT Id, Name, ProductCode,
                           Description, Destination__c
                    FROM Product2
                    WHERE IsActive = TRUE
                    AND Destination__c = :req.destination
                    WITH USER_MODE
                    ORDER BY Name
                    LIMIT 200
                ];

                if (products.isEmpty()) {
                    result.message =
                        'No active products found for ' +
                        req.destination + '.';
                    continue;
                }

                String htmlBody = buildEmail(
                    req.destination,
                    products
                );

                Messaging.SingleEmailMessage email =
                    new Messaging.SingleEmailMessage();

                email.setToAddresses(
                    new String[] { recipient }
                );

                email.setSubject(
                    'VGTS Travel Options - ' +
                    req.destination
                );

                email.setHtmlBody(htmlBody);

                email.setPlainTextBody(
                    'Hello,\n\n' +
                    'Please find our available travel products ' +
                    'for ' + req.destination +
                    ' in the HTML version of this email.\n\n' +
                    'Best regards,\nVGTS Sales Team'
                );

                email.setSaveAsActivity(false);

                emails.add(email);
                responseIndexes.add(responses.size() - 1);

                result.productsSent = products.size();

            } catch (Exception e) {
                result.message =
                    'Unable to prepare the product catalog: ' +
                    e.getMessage();
            }
        }

        if (!emails.isEmpty()) {

            Messaging.SendEmailResult[] sendResults =
                Messaging.sendEmail(emails, false);

            for (Integer i = 0; i < sendResults.size(); i++) {

                Response result =
                    responses[responseIndexes[i]];

                if (sendResults[i].isSuccess()) {

                    result.success = true;

                    result.message =
                        'VGTS product catalog successfully submitted to the customer email address.';

                } else {

                    result.success = false;

                    result.message =
                        'Email sending failed: ' +
                        sendResults[i].getErrors()[0].getMessage();

                    result.productsSent = 0;
                }
            }
        }

        return responses;
    }

    private static String buildEmail(
        String destination,
        List<Product2> products
    ) {

        String html =
            '<html><body style="margin:0;padding:20px;' +
            'background:#f3f6fa;font-family:Arial,sans-serif;">';

        html +=
            '<table width="100%" cellpadding="0" cellspacing="0" ' +
            'style="max-width:700px;margin:auto;background:#ffffff;' +
            'border-radius:12px;">';

        html +=
            '<tr><td style="background:#123c69;padding:30px;' +
            'text-align:center;color:white;">' +
            '<h1 style="margin:0;">VGTS</h1>' +
            '<p style="margin:10px 0 0;">Your Travel Options</p>' +
            '</td></tr>';

        html +=
            '<tr><td style="padding:28px;">' +
            '<h2 style="color:#123c69;">Available travel products for ' +
            escapeHtml(destination) + '</h2>' +
            '<p style="color:#555;">Hello,</p>' +
            '<p style="color:#555;line-height:1.6;">' +
            'Thank you for your interest in VGTS. ' +
            'Please find below our available travel options.</p>';

        for (Product2 p : products) {

            html +=
                '<table width="100%" cellpadding="0" cellspacing="0" ' +
                'style="border:1px solid #e2e8f0;' +
                'border-radius:10px;margin:20px 0;">';

            html +=
                '<tr><td style="background:#eaf1f8;' +
                'padding:16px;">' +
                '<h3 style="color:#123c69;margin:0;">' +
                escapeHtml(p.Name) +
                '</h3></td></tr>';

            html +=
                '<tr><td style="padding:18px;' +
                'color:#475569;line-height:1.8;">';

            html +=
                '<b>Product Code:</b> ' +
                escapeHtml(p.ProductCode) + '<br/>';

            html +=
                '<b>Destination:</b> ' +
                escapeHtml(p.Destination__c) + '<br/>';

            if (!String.isBlank(p.Description)) {
                html +=
                    '<br/><b>Description:</b><br/>' +
                    escapeHtml(p.Description);
            }

            html += '</td></tr></table>';
        }

        html +=
            '<p style="color:#555;line-height:1.6;">' +
            'For additional information, pricing or booking assistance, ' +
            'please contact our VGTS sales team.</p>' +
            '<p style="color:#123c69;font-weight:bold;">' +
            'Best regards,<br/>VGTS Sales Team</p>';

        html +=
            '</td></tr>' +
            '<tr><td style="background:#123c69;padding:18px;' +
            'text-align:center;color:white;font-size:12px;">' +
            'VGTS | Travel with Confidence' +
            '</td></tr></table></body></html>';

        return html;
    }

    private static String escapeHtml(String value) {

        if (value == null) {
            return '';
        }

        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }
}

