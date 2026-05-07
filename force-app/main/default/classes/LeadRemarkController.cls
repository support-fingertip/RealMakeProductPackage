public without sharing class LeadRemarkController {

    @AuraEnabled
    public static void addRemark(String leadId, String newRemark) {
        if (String.isBlank(newRemark) || String.isBlank(newRemark.trim())) {
            throw new AuraHandledException('Remark text cannot be empty.');
        }

        // Remove multiple consecutive blank lines
        newRemark = newRemark.replaceAll('(\\r\\n|\\n|\\r){2,}', '\n').trim();

        Lead__c leadRecord = [
            SELECT Id, Last_Notes__c, Lead_Status__c, RecordType.Name
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];

        User currentUser = [
            SELECT Id, Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        String recordTypeName = leadRecord.RecordType != null ? leadRecord.RecordType.Name : 'N/A';
        String leadStatus = String.isNotBlank(leadRecord.Lead_Status__c) ? leadRecord.Lead_Status__c : 'N/A';
        String userName = currentUser.Name;

        Datetime dt = Datetime.now();
        String formattedDateTime = dt.format('dd-MM-yy HH:mm a', 'Asia/Kolkata');

        Integer remarkNumber = 1;
        String existingNotes = leadRecord.Last_Notes__c;

        if (String.isNotBlank(existingNotes)) {
            List<String> existingLines = existingNotes.split('\n');
            List<String> nonEmptyLines = new List<String>();
            for (String line : existingLines) {
                if (String.isNotBlank(line)) {
                    nonEmptyLines.add(line);
                }
            }
            remarkNumber = nonEmptyLines.size() + 1;
        }

        String formattedRemark = 'Remark ' + remarkNumber + ': [' + recordTypeName + '] '
            + userName + ' - [' + leadStatus + '] [' + formattedDateTime + ']: ' + newRemark;

        if (String.isBlank(existingNotes)) {
            leadRecord.Last_Notes__c = formattedRemark;
        } else {
            leadRecord.Last_Notes__c = existingNotes + '\n' + formattedRemark;
        }

        update leadRecord;
    }

    @AuraEnabled
    public static List<String> fetchRemarks(String leadId) {
        Lead__c leadRecord = [
            SELECT Id, Last_Notes__c
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];

        List<String> remarks = new List<String>();

        if (leadRecord != null && String.isNotBlank(leadRecord.Last_Notes__c)) {
            for (String line : leadRecord.Last_Notes__c.split('\n')) {
                if (String.isNotBlank(line)) {
                    remarks.add(line);
                }
            }

            // Reverse to show latest first (descending order)
            List<String> reversed = new List<String>();
            for (Integer i = remarks.size() - 1; i >= 0; i--) {
                reversed.add(remarks[i]);
            }
            remarks = reversed;
        }

        return remarks;
    }

}