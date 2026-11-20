
public with sharing class VGTSProductCardAction {

    public class Request {
        @InvocableVariable(
            label='Destination'
            required=true
        )
        public String destination;
    }

    public class Response {
        @InvocableVariable(label='Product Cards')
        public List<VGTSProductCard> products;

        @InvocableVariable(label='Result Message')
        public String message;
    }

    @InvocableMethod(
        label='Search VGTS Product Cards'
        description='Searches active VGTS travel products by destination.'
    )
    public static List<Response> search(List<Request> requests) {

        List<Response> responses = new List<Response>();

        for (Request req : requests) {

            Response result = new Response();
            result.products = new List<VGTSProductCard>();

            if (String.isBlank(req.destination)) {
                result.message = 'Please provide a destination.';
                responses.add(result);
                continue;
            }

            List<Product2> records = [
                SELECT Id, Name, ProductCode,
                       Description, Destination__c
                FROM Product2
                WHERE IsActive = TRUE
                AND Destination__c = :req.destination
                WITH USER_MODE
                ORDER BY Name
                LIMIT 200
            ];

            for (Product2 p : records) {

                VGTSProductCard card = new VGTSProductCard();

                card.productId = p.Id;
                card.name = p.Name;
                card.productCode = p.ProductCode;
                card.destination = p.Destination__c;
                card.description = p.Description;

                result.products.add(card);
            }

            result.message = result.products.isEmpty()
                ? 'No matching products found.'
                : 'Matching VGTS products retrieved successfully.';

            responses.add(result);
        }

        return responses;
    }
}

