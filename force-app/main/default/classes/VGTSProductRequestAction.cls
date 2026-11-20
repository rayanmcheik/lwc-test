
public with sharing class VGTSProductRequestAction {

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

        @InvocableVariable(label='Destination')
        public String destination;

        @InvocableVariable(label='Customer Email')
        public String customerEmail;
    }

    @InvocableMethod(
        label='Submit VGTS Product Request'
        description='Receives the travel destination and customer email for a VGTS product catalog request.'
    )
    public static List<Response> submitRequest(
        List<Request> requests
    ) {

        List<Response> results = new List<Response>();

        for (Request req : requests) {

            Response res = new Response();

            res.success = false;
            res.destination = req.destination;
            res.customerEmail = req.customerEmail;

            if (String.isBlank(req.destination)) {
                res.message = 'Destination is required.';
            }
            else if (String.isBlank(req.customerEmail) ||
                !Pattern.matches(
                    '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$',
                    req.customerEmail.trim()
                )) {

                res.message = 'A valid customer email is required.';
            }
            else {
                res.success = true;
                res.message =
                    'Product request information received successfully.';
            }

            results.add(res);
        }

        return results;
    }
}

