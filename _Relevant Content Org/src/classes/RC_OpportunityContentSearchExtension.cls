/*
	RC_OpportunityContentSearchExtension - Controller extends Opportunity and controls content search
		Provides a list of relevant content for the opportunity based on keywords (default: RC_Keywords__c)
	Author: Mike Hineline
	
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
public with sharing class RC_OpportunityContentSearchExtension {
	// Member variable to hold current account object
	private final Opportunity thisOpportunity;
	// Member variable for the start position of the search, used for pagination
	public Integer maxResults {get; set;}
	// Member variable for the number of search results displayed per page
	public Integer resultsPerPage {get; set;}
	// Member variable for the number of total pages of results in the total list
	public Integer numPages {get; private set;}
	// Member variable for the current page that is being viewed
	public Integer currentPage {get; set;}
	// Member variable for holding page numbers for pagination iteration in Visualforce
	public List<Integer> resultPages {get; private set;}
	// Member variable for the total number of search results available, used for pagination
	public Integer totalResults {get; private set;}
	// Member variable to store whether or not Content is available in this org to this user
	public Boolean contentAvailable {get; private set;}
	// Member variable for the way Content is handled ('Content' if Content is available to the User or 'File' otherwise)
	public String contentType {get; private set;}

	// Member variable for the full list of Opportunity's Related Content data (up to totalResults in size)
	public List<ContentVersionContainer> opportunityContentAll {get; private set;}
	// Member variable for the Opportunity's Related Content data displayed on the current page
	public List<ContentVersionContainer> opportunityContentPage {get; private set;}

	// Member variable for the Opportunity's Keywords 
	public String opportunitySearchString {get; set;}

	/*
		Constructor to initialize the Content list based on the Opportunity.RC_Keywords__c
	*/
    public RC_OpportunityContentSearchExtension(ApexPages.StandardController controller) {
    	// Set the current Opportunity object from the standard controller
        this.thisOpportunity = (Opportunity)controller.getRecord();
        // Default maximum number of results queried to 100
        maxResults = 100;
        // Default number of results returned per page
        // Note: if you increase this to >20, you'll need to update the test code coverage
        // 	RC_OpportunityContentSearchExt_test.RC_OpportunityContentSearchExtensionTestMethod 
        //	Set NUM_TEST_CONTENT_1 > than this resultsPerPage value
        resultsPerPage = 10;
        // Default number of pages of results to 1
        numPages = 1;
        // Initialize the page list with page number 1
        resultPages = new List<Integer>{1};
        // Default current page being viewed to 1
        currentPage = 1;
        // Initialize the totalResults to 0
        totalResults = 0;
        // Initialize the content availability and type (Content or File)
        contentAvailable = contentAvailableCheck();
        if (contentAvailable) {
        	contentType = 'Content';
        } else {
        	contentType = 'File';
        }

		// Perform the initial search with the opportunity RC_Keywords__c as the search string
       	opportunityContentAll = new List<ContentVersionContainer>();
       	opportunityContentPage = new List<ContentVersionContainer>();
       	if (this.thisOpportunity.Id != null) {
       		opportunitySearchString = thisOpportunity.RC_Keywords__c;
			performSearch(opportunitySearchString);
       	}
    }
    
    /*
		ContentVersionContainer - class for storing Task sObject & related information
	*/
    public class ContentVersionContainer {
    	// Getter/Setter for the contained Task sObject
        public ContentVersion contentVersionSObject {get; private set;}
        // Member variable for the formatted date string
        public String contentModifiedDateFormatted {get; private set;}
        // Member variable for the formatted file type string
        public String fileTypeFormatted {get; private set;}

        // Overloaded constructor to initialize formatted strings when given a ContentVersion input
        public ContentVersionContainer(ContentVersion c) {
            contentVersionSObject = c;

            // Format the date string
            contentModifiedDateFormatted = '';
            if (c.ContentModifiedDate != null) {
            	contentModifiedDateFormatted = c.ContentModifiedDate.month() + '/' + c.ContentModifiedDate.day() + '/' + c.ContentModifiedDate.year();
            }

            // Format the FileType string
            fileTypeFormatted = '';
            if (c.FileType != null) {
            	fileTypeFormatted = cleanFileType(c.FileType);
            }
        }
    }
    
	/*
		performSearch - method to perform the content search and update the relevant content lists
		Inputs:
		- String searchString - the search string on which the content should be searched
		Returns: none
		Actions:
		- Update this.opportunityContentAll with all search results
		- Update this.opportunityContentPage with the current page search results
		- Update this.totalResults with full count of results
		- Update this.numPages with number of pages of content
	*/
    public void performSearch(String searchString) {
		/*
			Generate a list of keywords for the from the input searchString
			Two key variables:
				Set<String> keywordSearchSet - Set containing the keywords
				String keywordsSearchString - String containing the keywords separated by OR for SOSL
		*/
        // List of ignored keywords
        Set<String> stopWords = new Set<String>{'a', 'about', 'above', 'above', 'across', 'after', 'afterwards', 'again', 'against', 'all', 'almost', 'alone', 'along', 'already', 'also','although','always','am','among', 'amongst', 'amoungst', 'amount',  'an', 'and', 'another', 'any','anyhow','anyone','anything','anyway', 'anywhere', 'are', 'around', 'as',  'at', 'back','be','became', 'because','become','becomes', 'becoming', 'been', 'before', 'beforehand', 'behind', 'being', 'below', 'beside', 'besides', 'between', 'beyond', 'bill', 'both', 'bottom','but', 'by', 'call', 'can', 'cannot', 'cant', 'co', 'con', 'could', 'couldnt', 'cry', 'de', 'describe', 'detail', 'do', 'done', 'down', 'due', 'during', 'each', 'eg', 'eight', 'either', 'eleven','else', 'elsewhere', 'empty', 'enough', 'etc', 'even', 'ever', 'every', 'everyone', 'everything', 'everywhere', 'except', 'few', 'fifteen', 'fify', 'fill', 'find', 'fire', 'first', 'five', 'for', 'former', 'formerly', 'forty', 'found', 'four', 'from', 'front', 'full', 'further', 'get', 'give', 'go', 'had', 'has', 'hasnt', 'have', 'he', 'hence', 'her', 'here', 'hereafter', 'hereby', 'herein', 'hereupon', 'hers', 'herself', 'him', 'himself', 'his', 'how', 'however', 'hundred', 'ie', 'if', 'in', 'inc', 'indeed', 'interest', 'into', 'is', 'it', 'its', 'itself', 'keep', 'last', 'latter', 'latterly', 'least', 'less', 'ltd', 'made', 'many', 'may', 'me', 'meanwhile', 'might', 'mill', 'mine', 'more', 'moreover', 'most', 'mostly', 'move', 'much', 'must', 'my', 'myself', 'name', 'namely', 'neither', 'never', 'nevertheless', 'next', 'nine', 'no', 'nobody', 'none', 'noone', 'nor', 'not', 'nothing', 'now', 'nowhere', 'of', 'off', 'often', 'on', 'once', 'one', 'only', 'onto', 'or', 'other', 'others', 'otherwise', 'our', 'ours', 'ourselves', 'out', 'over', 'own','part', 'per', 'perhaps', 'please', 'put', 'rather', 're', 'same', 'see', 'seem', 'seemed', 'seeming', 'seems', 'serious', 'several', 'she', 'should', 'show', 'side', 'since', 'sincere', 'six', 'sixty', 'so', 'some', 'somehow', 'someone', 'something', 'sometime', 'sometimes', 'somewhere', 'still', 'such', 'system', 'take', 'ten', 'than', 'that', 'the', 'their', 'them', 'themselves', 'then', 'thence', 'there', 'thereafter', 'thereby', 'therefore', 'therein', 'thereupon', 'these', 'they', 'thickv', 'thin', 'third', 'this', 'those', 'though', 'three', 'through', 'throughout', 'thru', 'thus', 'to', 'together', 'too', 'top', 'toward', 'towards', 'twelve', 'twenty', 'two', 'un', 'under', 'until', 'up', 'upon', 'us', 'very', 'via', 'was', 'we', 'well', 'were', 'what', 'whatever', 'when', 'whence', 'whenever', 'where', 'whereafter', 'whereas', 'whereby', 'wherein', 'whereupon', 'wherever', 'whether', 'which', 'while', 'whither', 'who', 'whoever', 'whole', 'whom', 'whose', 'why', 'will', 'with', 'within', 'without', 'would', 'yet', 'you', 'your', 'yours', 'yourself', 'yourselves', 'the'};
		// Replace special characters with spaces
		//	spaces are used in place of removing the characters in case there is a string like "test-string")
		String cleanKeywords = searchString.replaceAll('[\\p{Punct}]',' ');
		// Put the space separated keywords into a List for manipulation
		List<String> workingKeywordList = new List<String>();
		workingKeywordList = cleanKeywords.split(' ');
		Set<String> keywordSearchSet = new Set<String>();
		String keywordSearchString = '';
		// Add the keywords ot the Set and string skipping stop words and blanks
		for (String s : workingKeywordList) {
			if (!stopWords.contains(s) && !s.isWhiteSpace()) {
				keywordSearchSet.add(s.toLowerCase());
				keywordSearchString += s + ' OR ';
			}
		}
		// Strip the trailing ' OR '
		keywordSearchString = keywordSearchString.removeEnd(' OR ');
		// DEBUG USE:
		// System.debug('=============================' + keywordSearchString);
		
		/*
			Perform the SOSL (case insensitive) search on ContentVersion for the keywordSearchString
				Require a minimum of 3 characters to search
				Maximum query size = this.maxResults
		*/
		// If Content is not available, limit the search to only non-Content (Files)
		String queryLimitString = '';
		if (contentAvailable == false) {
			queryLimitString = ' AND Origin<>\'C\'';
		}
		
		// Clear the existing lists
	    this.opportunityContentAll.clear();
		this.opportunityContentPage.clear();
		
		// Peform the search
       	List<ContentVersion> returnContent = new List<ContentVersion>();
		if (keywordSearchString.length() > 2) {
			String contentQueryString = 'FIND :keywordSearchString IN ALL FIELDS';
			contentQueryString += ' RETURNING ContentVersion (Id, Title, FileType, Description, TagCsv, ContentSize, ContentDocumentId, ContentModifiedDate, IsDeleted';
			contentQueryString += ' WHERE IsLatest = TRUE AND IsDeleted = FALSE';
	        contentQueryString += queryLimitString;
	        contentQueryString += ')';
	        contentQueryString += ' LIMIT ' + this.maxResults;
	        List<List<ContentVersion>> rawContentList = search.query(contentQueryString);

		    // Add any non-deleted content to the full result list and current page list member variables
		    // 	Removing deleted entries manually since SOSL queries don't allow for a WHERE clause
	    	Integer i = 0;
			for (ContentVersion c : rawContentList[0]) {
				// Add the content to the full result list
        		this.opportunityContentAll.add( new ContentVersionContainer(c) );
		    	//  Add the content for the current page list
		    	//		A new search always starts at the beginning of the results (i=0)
				if (i < this.resultsPerPage) {
	        		this.opportunityContentPage.add( new ContentVersionContainer(c) );
				}
	       		i++;
			}
	    	// Set them member variable for the total number of results
	    	this.totalResults = this.opportunityContentAll.size();
	    	// Set the total number of pages of content
	    	if (this.resultsPerPage > 0) {
		    	this.numPages = (Integer)Math.ceil((Decimal)this.totalResults / (Decimal)this.resultsPerPage);
	    	} else {
	    		this.numPages = 1;
	    	}
	    	// Update the list of page numbers
	    	this.resultPages.clear();
	    	for (Integer x = 0; x < this.numPages; x++) {
	    		this.resultPages.add(x + 1);
	    	} 
		}
    }
    
	/*
		updateSearch - method to update the Search results using the searchButton on the Visualforce page
		Inputs: none, but references this.opportunitySearchString which is input by the Visualforce page
		Returns:
			- null PageReference (Visualforce re-renders pageBlock)
		Actions:
			- Performs a new search via performSearch()
	*/
    public PageReference updateSearch() {
    	// Perform the search with the current member variables which were updated by the Visualforce page
		performSearch(this.opportunitySearchString);

		// Return null to stay on the same page; Visualforce re-renders the list
		return null;
    }

	/*
		changePage - method to update the Search results display by moving to a different section of the
			search results
		Inputs: none, but references this.currentPage which is input by the Visualforce page
		Returns:
			- null PageReference (Visualforce re-renders pageBlock)
		Actions:
			- Updates the opportunityContentPage List in the view state
	*/
    public PageReference changePage() {
    	// Ensure currentPage requested is between 1 and this.numPages
    	if (this.currentPage < 1) {
    		this.currentPage = 1;
    	} else if (this.currentPage >= this.numPages) {
    		this.currentPage = this.numPages;
    	}

    	// Determine the start and end position based on this.currentPage, which was set by the Visualforce page
    	Integer startPos = (this.currentPage - 1) * this.resultsPerPage;
    	Integer endPos = startPos + this.resultsPerPage;
    	
		// Replace this.OpportunityContentPage with the results from this.opportunityContentAll
		//		for the requested section of results
		this.opportunityContentPage.clear();
	    Integer i = 0;
		for (ContentVersionContainer c : this.opportunityContentAll) { 
			if (i >= startPos && i < endPos ) {
        		this.opportunityContentPage.add( new ContentVersionContainer(c.contentVersionSObject) );
			}
			i++;
		}

		// Return null to stay on the same page; Visualforce re-renders the list
		return null;
    }
    
   	/*
		cleanFileType - method to return a 3-4 character filetype for a known input ContentVersion.FileType string
		Inputs:
		- String inputFileTypeString - input string in format used by ContentVersion.FileType
		Returns: 
		- String outputFileTypeString - 3-4 character string for recognized extensions
			or original input string for unrecognized extensions
	*/
    public static String cleanFileType(String inputFileTypeString) {
    	// Initialize the string to manipulate & output
		String outputFileTypeString = inputFileTypeString.toLowerCase();
		
		// Set the input/output file type string mappings
		Map<String, String> knownFileTypes = new Map<String, String> {
			'power_point' => 'ppt', 'power_point_m' => 'pptm', 'power_point_t' => 'potx', 'power_point_x' => 'pptx',
			'excel' => 'xls', 'excel_m' => 'xlsm', 'excel_t' => 'xltx', 'excel_x' => 'xlsx',
			'jpeg' => 'jpg', 'word' => 'doc', 'word_m' => 'docm', 'word_t' => 'dotx', 'word_x' => 'docx',
			'rfc822' => 'msg', 'text' => 'txt', 'visio' => 'vsd', 'flash' => 'swf'
		};
	
		// Attempt to match the input file type string to a known value
		String knownFileTypeString = knownFileTypes.get(outputFileTypeString);
		if (knownFileTypeString != null) {
			outputFileTypeString = knownFileTypeString;
		}

		return outputFileTypeString;
    }
    
   	/*
		contentAvailableCheck - method to determine if CRM Content is enabled for this user:
			1) Ensure enabled for the Org via 
				Setup | Salesforce CRM Content | Settings -> "Enable Salesforce CRM Content" is enabled
			2) Ensure enabled for the User via "Salesforce CRM Content User" feature license
		Inputs: none
		Returns: 
			- true - if CRM Content is available to the logged in user
			- false - if CRM Content is note available to the logged in user
	*/
	public static Boolean contentAvailableCheck() {
		// Initialize the return variable
		Boolean contentIsAvailable = false;
		
		// Determine if Content is enabled in the org by determining if the
		//	ContentWorkspace object is available
		Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
		Schema.SobjectType findContentWorkspace = gd.get('ContentWorkspace');
		if (findContentWorkspace != null) {
			// If the ContentWorkspace object is available, Content is enabled for the Org
			// Determine if Content is available to the logged in User
			User thisUser = [SELECT Id, UserPermissionsSFContentUser
				FROM User u WHERE u.Id = :Userinfo.getUserId()
				LIMIT 1];
			if (thisUser.UserPermissionsSFContentUser == true) {
				contentIsAvailable = true;
			} else {
				contentIsAvailable = false;
			}
		} else {
			// If the ContentWorkspace object is not available, Content is not enabled
			contentIsAvailable = false;
		}
		
		// Return the content availability
		return contentIsAvailable;
	}
    
}