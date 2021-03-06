/*
    Unit tests to cover:
    - RC_RelevantContentOpportunity Visualforce page
    - RC_OpportunityContentSearchExtension Apex class (controller extension for Visualforce page)
    
    Copyright (c) 2013, salesforce.com, Inc.
    All rights reserved.
    
    Redistribution and use in source and binary forms, with or without modification, 
    are permitted provided that the following conditions are met:
    
        * Redistributions of source code must retain the above copyright notice, 
        this list of conditions and the following disclaimer.
        * Redistributions in binary form must reproduce the above copyright notice, 
        this list of conditions and the following disclaimer in the documentation 
        and/or other materials provided with the distribution.
        * Neither the name of the salesforce.com, Inc. nor the names of its contributors 
        may be used to endorse or promote products derived from this software 
        without specific prior written permission.
    
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
    IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
    INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
    LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
    OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED 
    OF THE POSSIBILITY OF SUCH DAMAGE.
*/
@isTest
private class RC_OpportunityContentSearchExt_test {

    // CreateContent - utility method to create test Content and return them in a List
    // Inputs:
    //  basename = beginnging of ContentVersion.Title string, to be concatenated with an incrementing integer
    //  objectCount = number of test records to be created
    //	contentType
    //		C = Try to create Content, if possible
    //		H = Try to create Files
    // Output:
    //  List<ContentVersion> = list containing the records created
    public static List<ContentVersion> CreateContent(String basename, Integer objectCount, String contentType) {
        // List to hold the Task sObjects
        List<ContentVersion> newContent = new List<ContentVersion>();
        
        // Create a blob to represent the file
		Blob testBlob = Blob.valueof('TestFileBlob');

		// Set the appropriate Content type (Content or File)
		String contentOrigin = 'C';
		Boolean contentAvailableContentTest = RC_OpportunityContentSearchExtension.contentAvailableCheck();
		if (contentType == 'C' && contentAvailableContentTest == true) {
			// Content is requested and available, set origin to 'C' (Content)
			contentOrigin = 'C';
		} else {
			// Content is not available or not requested, set origin to 'H' (File)
			contentOrigin = 'H';
		}
        
        // Fill the list with test records with names initialized based on basename
        for(Integer i=0; i<objectCount; i++) {
			// Create the Content/File
            newContent.add(new ContentVersion(
            	Title = basename + String.valueof(i),
            	Origin = contentOrigin,
            	PathOnClient = basename + String.valueof(i),
            	VersionData = testBlob)
			);
        }
        
        // Return the list of records created
        return newContent;
    }

    // Test the myTaskList page and controller
    static testMethod void RC_OpportunityContentSearchExtensionTestMethod() {
    	/*
    		Determine if content is available for the org
    			Will determine if Content or Files is used for tests
    	*/
    	Boolean contentAvailableTest = RC_OpportunityContentSearchExtension.contentAvailableCheck();
    	
    	/*
    		Test to ensure RC_Keywords__c is holding the Opportunity.Name
    		Note: RC_Keywords__c is an admin editable formula so if it is modified to remove the Opportunity Name, this will fail
    	*/
        // Create a test opportunity which will contain the RC_Keywords__c formula field
        Opportunity testOpportunity = new Opportunity(Name='Test Opportunity',CloseDate=Date.today()+365,StageName='Prospecting');
        insert testOpportunity;
        // Query the test opportunity to get the calculated value of the RC_Keywords__c formula field
		testOpportunity = [SELECT ID, Name, RC_Keywords__c from Opportunity WHERE ID = :testOpportunity.id];
		// Ensure the Keyword__c includes 'Test' (from the Opportunity.Name)
        System.assert(testOpportunity.RC_Keywords__c.contains('Test'));
        
        // Initialize first batch test data by adding test data for required fields and inserting
        //	This content contains the word 'Test' and should match the RC_Keywords__c which includes the opportunity Title of 'Test Opportunity'
        final Integer NUM_TEST_CONTENT_1 = 20;
        List<ContentVersion> testContentPos = CreateContent('Test Content ',NUM_TEST_CONTENT_1,'C');
        for(ContentVersion thisContentPos: testContentPos) {
			thisContentPos.Description = 'Test';
        }
        insert testContentPos;

        // Initialize second batch test data by adding test data for required fields and inserting
        //	This content does not contain any words relevant to RC_Keywords__c which includes the opportunity Title of 'Test Opportunity'
        final Integer NUM_TEST_CONTENT_2 = 10;
        List<ContentVersion> testContentNeg = CreateContent('Irrelevant',NUM_TEST_CONTENT_2,'C');
        for(ContentVersion thisContentNeg: testContentNeg) {
			thisContentNeg.Description = 'Irrelevant';
        }
        insert testContentNeg;

        /*
        	Constructor test
        		Test the member variables and query resulting from the initialization of the search using RC_Keywords__c
        */
		// Since SOSL queries return an empty set, force the addition of the first batch of test data
		//  to the SOSL results
		Map<Id, ContentVersion> searchById = new Map<Id, Contentversion>([SELECT Id FROM ContentVersion WHERE Description='Test']);
		List<Id> searchResults = new List<id>(searchById.keySet());
		Test.setFixedSearchResults(searchResults);

        // Set Visualforce page
        PageReference page = new PageReference('RC_RelevantContentOpportunity');
        Test.setCurrentPage(page); 
		// Ensure CONTENT_ONLY is set to false for tests
		RC_OpportunityContentSearchExtension.CONTENT_ONLY = false;
        // Set the standard controller and extension
        ApexPages.StandardController controller = new ApexPages.StandardController(testOpportunity);
		RC_OpportunityContentSearchExtension controllerExtension = new RC_OpportunityContentSearchExtension(controller);
        // Test that NUM_TEST_CONTENT_1 of ContentVersion were added to opportunityContentAll and totalResults
        System.assert(controllerExtension.opportunitySearchString.contains('Test'));
        System.assertEquals(NUM_TEST_CONTENT_1,controllerExtension.opportunityContentAll.size());
        System.assertEquals(NUM_TEST_CONTENT_1,controllerExtension.totalResults); 
        System.assertEquals(1,controllerExtension.currentPage); 
        // Test that opportunityContentPage only contains <= RESULTS_PER_PAGE
        System.assert(controllerExtension.opportunityContentPage.size() <= controllerExtension.RESULTS_PER_PAGE);
        // Test the number of pages = ceil(NUM_TEST_CONTENT_1 / RESULTS_PER_PAGE)
        Integer testNumPages = (Integer)Math.ceil((Decimal)controllerExtension.totalResults / (Decimal)controllerExtension.RESULTS_PER_PAGE);
        System.assertEquals(testNumPages,controllerExtension.numPages);

        /*
        	Test the cleanFileType and getIconFilename methods
        	Send in known and unknown values and test results
        */
        // Test that cleanFileType and getIconFilename handled a known value correctly
        String fileTypeTest = 'EXCEL_X';
        String fileNameTest = 'test.xlsx';
        String fileTypeTestOutput = RC_OpportunityContentSearchExtension.cleanFileType(fileTypeTest,fileNameTest);
        System.assertEquals('xlsx',fileTypeTestOutput);
        String filenameTestOutput = RC_OpportunityContentSearchExtension.getIconFilename(fileTypeTestOutput);
        System.assertEquals('excel.svg',filenameTestOutput);
        // Test that cleanFileType and getIconFilename handled an unknown value with no file extension correctly
        fileTypeTest = 'UNKNOWN_FILE_TYPE_STRING_TEST';
        fileNameTest = 'unknownfile';
        fileTypeTestOutput = RC_OpportunityContentSearchExtension.cleanFileType(fileTypeTest,fileNameTest);
        System.assertEquals('unknown_file_type_string_test',fileTypeTestOutput);
        filenameTestOutput = RC_OpportunityContentSearchExtension.getIconFilename(fileTypeTestOutput);
        System.assertEquals('unknown.svg',filenameTestOutput);
        // Test that cleanFileType and getIconFilename handled an unknown value with a file extension correctly
        fileTypeTest = 'UNKNOWN_FILE_TYPE_STRING_TEST';
        fileNameTest = 'unknownfile.wmv';
        fileTypeTestOutput = RC_OpportunityContentSearchExtension.cleanFileType(fileTypeTest,fileNameTest);
        System.assertEquals('wmv',fileTypeTestOutput);
        filenameTestOutput = RC_OpportunityContentSearchExtension.getIconFilename(fileTypeTestOutput);
        System.assertEquals('video.svg',filenameTestOutput);
        
        /*
        	Test the changePage method
        */
        // Save the first (page 1) content Id
        Id opportunityContentPage1Id = controllerExtension.opportunityContentPage[0].contentVersionSObject.Id;
        // Test for changes in page out of range < 1
        controllerExtension.currentPage = 0;
        controllerExtension.changePage();
        System.assertEquals(1,controllerExtension.currentPage); 
        // Test for changes in page out of range > numPages
        controllerExtension.currentPage = controllerExtension.numPages + 1;
        controllerExtension.changePage();
        System.assertEquals(controllerExtension.numPages,controllerExtension.currentPage); 
        // Test for change to the 2nd page of results
        controllerExtension.currentPage = 2;
        controllerExtension.changePage();
        if (controllerExtension.numPages > 1) {
	        System.assertEquals(2,controllerExtension.currentPage); 
	        // Ensure the content has changed from page 1 to page 2
	        System.assertNotEquals(opportunityContentPage1Id, controllerExtension.opportunityContentPage[0].contentVersionSObject.Id);
        } else {
        	// Test that we're still on the 1st page if there is only 1 page of results
        	// This can happen if RESULTS_PER_PAGE in the controller extension is set to 
			//	greater than NUM_TEST_CONTENT_1 above
	        System.assertEquals(1,controllerExtension.currentPage); 
        }

        /*
        	Test the updateSearch method - test for Irrelevant
        	Search for 'Irrelevant' and NUM_TEST_CONTENT_2 should be found
        */
		// Since SOSL queries return an empty set, force the addition of the second batch of test data
		//  to the SOSL results
		searchById = new Map<Id, Contentversion>([SELECT Id FROM ContentVersion WHERE Description='Irrelevant']);
		searchResults = new List<id>(searchById.keySet());
		Test.setFixedSearchResults(searchResults);
        controllerExtension.opportunitySearchString = 'Irrelevant';
        controllerExtension.updateSearch();
        System.assertEquals(NUM_TEST_CONTENT_2,controllerExtension.opportunityContentAll.size()); 
        System.assertEquals(NUM_TEST_CONTENT_2,controllerExtension.totalResults);
        
        /*
        	Test for User access to Content
        	Check outputs set by the contentAvailableCheck() method
        */
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User'];
        // Set up negative test user with no access to CRM Content
        User uNegative = new User(Alias = 'standtf', Email='unegative@mailinator.com',
				EmailEncodingKey='UTF-8', LastName='Test', LanguageLocaleKey='en_US',
				LocaleSidKey='en_US', ProfileId = p.Id,
        		TimeZoneSidKey='America/Chicago', UserName='unegative@relevantcontent.testuser',
        		UserPermissionsSFContentUser = false);
        // Instantiate the controller as the negative test user and test 
    	System.runAs(uNegative) {
	        // Set the standard controller and extension
    	    controller = new ApexPages.StandardController(testOpportunity);
			controllerExtension = new RC_OpportunityContentSearchExtension(controller);
			// Ensure contentAvailable is set to false for the user
			System.assertequals(false,controllerExtension.contentAvailable);
			// Ensure contentType is set correctly for the user
			if (RC_OpportunityContentSearchExtension.CONTENT_ONLY == false) {
				// Ensure content Type is set to 'Files' for the user
				System.assertequals('File',controllerExtension.contentType);
			} else {
				// No results can be returned with CONTENT_ONLY = true and no access to Content
				// Ensure MAX_RESULTS = 0
				System.assertequals(0,controllerExtension.MAX_RESULTS); 	
			}
        }

        // Set up positive test user with access to CRM Content
        User uPositive = new User(Alias = 'standtp', Email='upositive@mailinator.com',
				EmailEncodingKey='UTF-8', LastName='Test', LanguageLocaleKey='en_US',
				LocaleSidKey='en_US', ProfileId = p.Id,
        		TimeZoneSidKey='America/Chicago', UserName='upositive@relevantcontent.testuser',
        		UserPermissionsSFContentUser = true);
        // Instantiate the controller as the positive test user and test 
        //  Only test if Content is enabled for the Org
    	System.runAs(uPositive) {
			if (contentAvailableTest == true) {
	        	// Set the standard controller and extension
    	    	controller = new ApexPages.StandardController(testOpportunity);
				controllerExtension = new RC_OpportunityContentSearchExtension(controller);
				// Ensure contentAvailable is set to false for the user
				System.assertequals(true,controllerExtension.contentAvailable);
				// Ensure contentType is set to 'Content' for the user
				System.assertequals('Content',controllerExtension.contentType);
			}
        }
        
    }
    
    // Test the postFileToFeed webservice
    //	Reading from OpportunityFeed requires seeAllData = true
    @isTest(seeAllData = true)
    static void RC_FeedPostTestMethod() {
        // Create a test opportunity which will contain the RC_Keywords__c formula field
        Opportunity testOpportunity = new Opportunity(Name='Test Opportunity',CloseDate=Date.today()+365,StageName='Prospecting');
        insert testOpportunity;
        // Query the test opportunity to get the calculated value of the RC_Keywords__c formula field
		testOpportunity = [SELECT ID, Name, RC_Keywords__c from Opportunity WHERE ID = :testOpportunity.id];
		// Ensure the Keyword__c includes 'Test' (from the Opportunity.Name)
        System.assert(testOpportunity.RC_Keywords__c.contains('Test'));
        
        // Create a File for testing attachment
        //	This content contains the word 'Test' and should match the RC_Keywords__c which includes the opportunity Title of 'Test Opportunity'
        Integer numTestContent = 3;
        List<ContentVersion> testContentPos = CreateContent('Test Content ',numTestContent,'H');
        for(ContentVersion thisContentPos: testContentPos) {
			thisContentPos.Description = 'Test';
        }
        insert testContentPos;

       	// Since SOSL queries return an empty set, force the addition of the first batch of test data
		//  to the SOSL results
		Map<Id, ContentVersion> searchById = new Map<Id, Contentversion>([SELECT Id FROM ContentVersion WHERE Description='Test']);
		List<Id> searchResults = new List<id>(searchById.keySet());
		Test.setFixedSearchResults(searchResults);
		
        // Set Visualforce page
        PageReference page = new PageReference('RC_RelevantContentOpportunity');
        Test.setCurrentPage(page); 

		// Ensure CONTENT_ONLY is set to false for tests
		RC_OpportunityContentSearchExtension.CONTENT_ONLY = false;
        
        // Set the standard controller and extension
		ApexPages.StandardController controller = new ApexPages.StandardController(testOpportunity);
		RC_OpportunityContentSearchExtension controllerExtension = new RC_OpportunityContentSearchExtension(controller);
        
		/*
			Test the postFileToFeed remote static action
		*/
		// Test adding content with a comment
		String testComment = 'This is a test comment';
		// Call the postFileToFeed remote method and ensure it returns true
   	    Boolean postResult = RC_OpportunityContentSearchExtension.postFileToFeed(testContentPos[0].Id,testOpportunity.Id,testComment);
        System.assertEquals(true,postResult);
        // Query the inserted record (there will only be one feed item at this point in this test data)
        OpportunityFeed[] testFeedItems = [Select Id,RelatedRecordId,Type,Body,ParentId From OpportunityFeed WHERE ParentId = :testOpportunity.Id ORDER BY CreatedDate DESC LIMIT 1];
       	// Validate FeedItem was added
       	System.assertEquals(testContentPos[0].Id,testFeedItems[0].RelatedRecordId);
       	System.assertEquals(testOpportunity.Id,testFeedItems[0].ParentId);
		System.assertEquals(testComment,testFeedItems[0].Body);
       	System.assertEquals('ContentPost',testFeedItems[0].Type);

		// Test adding content without a comment
		testComment = null;
		// Call the postFileToFeed remote method and ensure it returns true
   	    postResult = RC_OpportunityContentSearchExtension.postFileToFeed(testContentPos[1].Id,testOpportunity.Id,testComment);
        System.assertEquals(true,postResult);
        // Query the inserted record (there will only be one feed item at this point in this test data)
        testFeedItems = [Select Id,RelatedRecordId,Type,Body,ParentId From OpportunityFeed WHERE ParentId = :testOpportunity.Id ORDER BY CreatedDate DESC LIMIT 1];
       	// Validate FeedItem was added
       	System.assertEquals(testContentPos[1].Id,testFeedItems[0].RelatedRecordId);
       	System.assertEquals(testOpportunity.Id,testFeedItems[0].ParentId);
		System.assertEquals(testComment,testFeedItems[0].Body);
       	System.assertEquals('ContentPost',testFeedItems[0].Type);

		// Test adding content with an invalid Content ID
		testComment = 'test';
		// Call the postFileToFeed remote method and ensure it returns true
		postResult = RC_OpportunityContentSearchExtension.postFileToFeed('068F00000000000',testOpportunity.Id,testComment);
		// Ensure function returns false
        System.assertEquals(false,postResult);
    }
}