public with sharing class PdfToSvgController {

    private static final String CONVERT_API_URL = 'https://v2.convertapi.com/convert/pdf/to/svg';
    private static final String API_TOKEN = 'jHr6WMc514MEUTl5DirVkI8glc7RQFPO';

    @AuraEnabled
    public static List<Map<String, String>> convertPdfToSvg(String base64Data, String fileName) {
        if (String.isBlank(base64Data)) {
            throw new AuraHandledException('No PDF data provided.');
        }

        try {
            // Step 1: Call ConvertAPI to convert PDF to SVG
            HttpRequest req = new HttpRequest();
            req.setEndpoint(CONVERT_API_URL);
            req.setMethod('POST');
            req.setHeader('Authorization', 'Bearer ' + API_TOKEN);
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(120000);

            Map<String, Object> fileValue = new Map<String, Object>{
                'Name' => fileName,
                'Data' => base64Data
            };

            List<Map<String, Object>> parameters = new List<Map<String, Object>>{
                new Map<String, Object>{ 'Name' => 'File', 'FileValue' => fileValue },
                new Map<String, Object>{ 'Name' => 'StoreFile', 'Value' => true }
            };

            Map<String, Object> requestBody = new Map<String, Object>{
                'Parameters' => parameters
            };

            req.setBody(JSON.serialize(requestBody));

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() != 200) {
                throw new AuraHandledException(
                    'ConvertAPI error (HTTP ' + res.getStatusCode() + '): ' + res.getBody()
                );
            }

            // Step 2: Parse response to get SVG file URLs
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> files = (List<Object>) result.get('Files');

            if (files == null || files.isEmpty()) {
                throw new AuraHandledException('ConvertAPI returned no SVG files.');
            }

            // Step 3: Fetch each SVG file content
            List<Map<String, String>> svgPages = new List<Map<String, String>>();

            for (Object fileObj : files) {
                Map<String, Object> fileMap = (Map<String, Object>) fileObj;
                String svgUrl = (String) fileMap.get('Url');
                String svgFileName = (String) fileMap.get('FileName');

                HttpRequest svgReq = new HttpRequest();
                svgReq.setEndpoint(svgUrl);
                svgReq.setMethod('GET');
                svgReq.setTimeout(60000);

                HttpResponse svgRes = http.send(svgReq);

                if (svgRes.getStatusCode() == 200) {
                    svgPages.add(new Map<String, String>{
                        'fileName' => svgFileName,
                        'svgContent' => svgRes.getBody()
                    });
                }
            }

            if (svgPages.isEmpty()) {
                throw new AuraHandledException('Failed to download SVG files from ConvertAPI.');
            }

            return svgPages;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('PDF to SVG conversion failed: ' + e.getMessage());
        }
    }
}