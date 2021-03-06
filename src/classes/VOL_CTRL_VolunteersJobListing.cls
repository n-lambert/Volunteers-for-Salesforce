// Written by David Habib, copyright (c) 2010, 2011 Groundwire, 1402 3rd Avenue, Suite 1000, Seattle, WA 98101
// This program is free software; you can redistribute it and/or modify it under the terms of the 
// GNU General Public License version 3 as published by the Free Software Foundation. http://www.gnu.org/licenses/gpl.html

global virtual with sharing class VOL_CTRL_VolunteersJobListing {

    // page parameters that can get passed into the page to control its behavior.
    global ID campaignIdFilter { get; set; }
    global boolean ShowJobName { get; set; }
    global boolean ShowDescription { get; set; }
    global boolean ShowLocationAddress { get; set; }
    global boolean ShowLocationInfo { get; set; }
    global boolean ShowSkills { get; set; }
    global boolean ShowShifts { get; set; }
    
    
    // dummy contact record to bind the Contact SignUp form to.
    global Contact contact { 
        get {
            if (contact == null) contact = new Contact();
            return contact;
        }
        set; 
    }
    
    // dummy volunteer shift record, NO LONGER USED (replaced by vhTemp)
    global Volunteer_Shift__c vsTemp { get; set; }
    
    // dummy volunteer hours record, to bind the Group Size integer to, to get validation
    global Volunteer_Hours__c vhTemp {
        get {
            if (vhTemp == null) vhTemp = new Volunteer_Hours__c();
            return vhTemp;      
        }
        set;
    }
    
    // parameters set by the client before calling VolunteerShiftSignUp()   
    global ID jobIdSignUp { get; set; }
    global string shiftIdSignUp { get; set; }
    global string strJobDisplayName { get; set; }
    global string strShiftDisplayName { get; set; }
    
    // return parameters set by VolunteerShiftSignUp()
    // NOTE: while these are actually ID's, we need to make the type string so the client can clear them with null!
    global string contactIdSignUp { get; set; }
    global string volunteerHoursIdSignUp { get; set; }
    
    // the instance specific url to the css that can be modified by the user.
    global string strURLtoCSSFile { 
        get { 
            if (strURLtoCSSFile == null) {
                list<Document> listDocs = [SELECT Name, Id From Document WHERE Name = 'VolunteersJobListingCSS.css' LIMIT 1 ];
                if (listDocs.size() > 0) {
                    Document doc = listDocs[0];
                    string imageid = doc.id;
                    imageid = imageid.substring(0,15);
                    strURLToCSSFile = '/servlet/servlet.FileDownload?file=' + imageid;
                }
            }
            return strURLtoCSSFile;
        }       
        set;
    }  
    
    // constructor
    global VOL_CTRL_VolunteersJobListing() {
                
        // set default's for page parameters
        campaignIdFilter = null;
        ShowJobName = true;
        ShowDescription = true;
        ShowLocationAddress = true;
        ShowLocationInfo = true;
        ShowSkills = false;
        ShowShifts = true;
        
        // handle optional parameters (must use string, not ID, to handle null)
        map<string, string> params = ApexPages.currentPage().getParameters();
        string p = params.get('campaignId');
        if (p != null && p != '') campaignIdFilter = p;
        p = params.get('ShowJobName');
        if (p != null && p == '0') ShowJobName = false;
        p = params.get('ShowDescription');
        if (p != null && p == '0') ShowDescription = false;
        p = params.get('ShowLocationAddress');
        if (p != null && p == '0') ShowLocationAddress = false;
        p = params.get('ShowLocationInfo');
        if (p != null && p == '0') ShowLocationInfo = false;
        p = params.get('ShowSkills');
        if (p != null && p == '1') ShowSkills = true;
        p = params.get('ShowShifts');
        if (p != null && p == '0') ShowShifts = false;
        
        vhTemp.Number_of_Volunteers__c = 1;
        contactIdSignUp = null;
        volunteerHoursIdSignUp = null;
    }

    // The list of Volunteer Jobs.
    global list<Volunteer_Job__c> listVolunteerJobs { 
        get {
            if (listVolunteerJobs == null) {
                        
                listVolunteerJobs = new list<Volunteer_Job__c>();
                DateTime dtNow = system.Now().addHours(-1);
                
                if (campaignIdFilter != null) {
                    listVolunteerJobs = [select Id, Name, Campaign__c, Campaign__r.IsActive, Campaign__r.Name, Campaign__r.StartDate, 
                        Description__c, Location_Information__c, Number_of_Shifts__c, Skills_Needed__c,
                        Location_Street__c, Location_City__c, Location__c, Location_Zip_Postal_Code__c,
                        (Select Id, Start_Date_Time__c, Duration__c, Number_of_Volunteers_Still_Needed__c,
                            Description__c From Volunteer_Job_Slots__r 
                            where Start_Date_Time__c >= :dtNow 
                            order by Start_Date_Time__c) 
                        from Volunteer_Job__c where Campaign__c = :campaignIdFilter and Display_on_Website__c = true 
                        order by First_Shift__c, Campaign__r.StartDate, Campaign__r.Name, Name];
                } else {
                    listVolunteerJobs = [select Id, Name, Campaign__c, Campaign__r.IsActive, Campaign__r.Name, Campaign__r.StartDate, 
                        Description__c, Location_Information__c, Number_of_Shifts__c, Skills_Needed__c,
                        Location_Street__c, Location_City__c, Location__c, Location_Zip_Postal_Code__c,
                        (Select Id, Start_Date_Time__c, Duration__c, Number_of_Volunteers_Still_Needed__c,
                            Description__c From Volunteer_Job_Slots__r 
                        	where Start_Date_Time__c >= :dtNow                        
                            order by Start_Date_Time__c) 
                        from Volunteer_Job__c where Campaign__r.IsActive = true and Display_on_Website__c = true 
                        order by First_Shift__c, Campaign__r.StartDate, Campaign__r.Name, Name];
                }
                
            	// now remove any jobs whose shifts are all past date.
            	for (integer i = listVolunteerJobs.size() - 1; i >= 0; i--) {
            		Volunteer_Job__c job = listVolunteerJobs[i];
            		if (job.Number_of_Shifts__c > 0 && job.Volunteer_Job_Slots__r.size() == 0) {
            			listVolunteerJobs.remove(i);            		
            		}
            	}
                
            }
            return sortVolunteerJobs(listVolunteerJobs);
        }
        
        set;
    }
    
    global virtual list<Volunteer_Job__c> sortVolunteerJobs (list<Volunteer_Job__c> jobsList) {
    	list<Volunteer_Job__c> resultList = new list<Volunteer_Job__c>();
    	DateTime faroutFuture = System.Now().addYears(100);
    	
    	//create a map of earliest shift datetime to job list
    	map<DateTime, list<Volunteer_Job__c>> jobMap = new map<DateTime, list<Volunteer_Job__c>>();
    	
    	for (Volunteer_Job__c vj : jobsList) {
    		DateTime nextShift = faroutFuture;
    		
    		//if the job has no shifts, set it in the past so it appears first on the page, otherwise get the first shift
    		if (vj.Volunteer_Job_Slots__r.size() == 0) {
    			nextShift = faroutFuture.addYears(-200);
    		} else if (vj.Volunteer_Job_Slots__r.size() > 0) {
    			for (Volunteer_Shift__c vs : vj.Volunteer_Job_Slots__r) {
    				if (vs.Start_Date_Time__c < nextshift) {
    					nextShift = vs.Start_Date_Time__c;
    				}
    			}
    		}
    		
    		//if our map doesn't contain this shift, create a new list, otherwise add to the list
    		if (jobMap.get(nextShift) == null) {
    			jobMap.put(nextShift, new List<Volunteer_Job__c>());
    		}
    		jobMap.get(nextShift).add(vj);
    	}
    	
    	//use SF's standard sort method on the datetimes
    	list<DateTime> keys = new list<DateTime>(jobMap.keySet());
    	keys.sort();
    	
    	//rebuild list in order
    	for (DateTime key:keys) {
    		resultList.addAll(jobMap.get(key));
    	}
    	return resultlist;
    }
    
    global virtual boolean getVolunteersHasJobs() {
        return (listVolunteerJobs.size() > 0);
    }
    
    // action method to allow the javascript to clear this variable.
    // used when the confirmation dialog is closed.
    global virtual PageReference ClearVolunteerHoursIdSignUp() {
        volunteerHoursIdSignUp = null;
        return null;
    }
    
    // just before we insert the new Volunteer Hours record,
    // give clients a chance to set any additional information they want.
    global virtual void VolunteerHoursBeforeInsert(Volunteer_Hours__c vh) {
        
    }   
    
    global virtual PageReference VolunteerShiftSignUp() {
        // clear return variables in case we fail.
        contactIdSignUp = null;
        volunteerHoursIdSignUp = null;
                    
        contactIdSignUp = VOL_SharedCode.CreateContactOrLead(contact, true, true);
        
        // then create hours if it was successful.
        if (contactIdSignUp != null) {
            Volunteer_Hours__c vh = new Volunteer_Hours__c(Contact__c = contactIdSignUp, Volunteer_Job__c = jobIdSignUp);
            if (shiftIdSignUp != null && shiftIdSignUp != '') { vh.Volunteer_Shift__c = shiftIdSignUp; }
            vh.Number_of_Volunteers__c = vhTemp.Number_of_Volunteers__c;
            vh.Status__c = 'Web Sign Up';
            vh.Start_Date__c = system.today();
            VolunteerHoursBeforeInsert(vh); 
            insert vh;
            volunteerHoursIdSignUp = vh.Id;
        }
        
        // now recreate the temp contact object so permissions will treat the object as now,
        // and thus allow the user to edit its fields.
        Contact c2 = new Contact();
        c2.FirstName = contact.FirstName;
        c2.LastName = contact.LastName;
        c2.Email = contact.Email;
        c2.Phone = contact.Phone;
        c2.HomePhone = contact.HomePhone;
        c2.Department = contact.Department;
        contact = c2;
        
        return null;
    }

    //==================== TEST METHOD(s) ======================================
    global static testmethod void UnitTest1() {

        // set up intial test data
        Account acc = new Account(name='Test Individual Bucket Account');
        insert acc;
        Contact con = new Contact(Lastname='Testy', Firstname='Test', Email='test@testy.com', AccountId=acc.Id);
        insert con;
        Campaign cmp = new Campaign(recordtypeid=VOL_SharedCode.recordtypeIdVolunteersCampaign, name='Test Job Campaign', IsActive=true);
        insert cmp;
        Volunteer_Job__c job = new Volunteer_Job__c(name='Job1', campaign__c=cmp.Id, Display_on_Website__c=true);
        insert job;
        Volunteer_Shift__c shift = new Volunteer_Shift__c(Volunteer_Job__c=job.Id, Duration__c=1, Start_Date_Time__c=System.now());
        insert shift;        
        
        // specify our settings        
        System.Assert(VOL_SharedCode.VolunteersSettings != null);
        Volunteers_Settings__c settings = new Volunteers_Settings__c();
        settings.Signup_Creates_Contacts_If_No_Match__c = false; // this shouldn't affect this page!
        settings.Signup_Matches_Existing_Contacts__c = false;   // this shouldn't affect this page!
        settings.Signup_Bucket_Account_On_Create__c = 'Test Individual Bucket Account';
        VOL_SharedCode.getVolunteersSettingsForTests(settings);
        
        PageReference pageRef = Page.VolunteersJobListing;
        pageRef.getParameters().put('ShowJobName', '1');
        pageRef.getParameters().put('ShowDescription', '1');
        pageRef.getParameters().put('ShowLocationAddress', '1');
        pageRef.getParameters().put('ShowLocationInfo', '1');
        pageRef.getParameters().put('ShowShifts', '1');
        pageRef.getParameters().put('ShowSkills', '1');
        Test.setCurrentPage(pageRef); 

        //instantiate the controller 
        VOL_CTRL_VolunteersJobListing ctrl = new VOL_CTRL_VolunteersJobListing();
        System.AssertEquals(null, ctrl.campaignIdFilter);
        System.AssertEquals(true, ctrl.ShowJobName);
        System.AssertEquals(true, ctrl.ShowDescription);
        System.AssertEquals(true, ctrl.ShowLocationAddress);
        System.AssertEquals(true, ctrl.ShowLocationInfo);
        System.AssertEquals(true, ctrl.ShowShifts);
        System.AssertEquals(true, ctrl.ShowSkills);
        System.AssertEquals(null, ctrl.contact.Id);
        System.AssertEquals(null, ctrl.jobIdSignUp);
        System.AssertEquals(null, ctrl.shiftIdSignUp);
        System.AssertEquals(1, ctrl.vhTemp.Number_of_Volunteers__c);
        System.AssertEquals(null, ctrl.strJobDisplayName);
        System.AssertEquals(null, ctrl.strShiftDisplayName);
        System.AssertEquals(null, ctrl.contactIdSignUp);
        System.AssertEquals(null, ctrl.volunteerHoursIdSignUp);
        System.Assert(ctrl.strURLtoCSSFile == ctrl.strURLtoCSSFile);
        System.Assert(ctrl.listVolunteerJobs.size() > 0);
        
        integer cJobs = ctrl.listVolunteerJobs.size();
        Volunteer_Job__c job2 = new Volunteer_Job__c(name='Job2', campaign__c=cmp.Id, Display_on_Website__c=true);
        insert job2;
        ctrl.listVolunteerJobs = null;
        System.AssertEquals(cJobs + 1, ctrl.listVolunteerJobs.size());

        ctrl.ClearVolunteerHoursIdSignUp();
        
        // sign someone up
        System.AssertEquals(null, ctrl.contact.Id);
        System.AssertEquals(null, ctrl.volunteerHoursIdSignUp);
        ctrl.contact.FirstName = 'Test';
        ctrl.contact.LastName = 'Testy';
        ctrl.contact.Email = 'test@testy.com';
        ctrl.jobIdSignUp = job.id;
        ctrl.shiftIdSignUp = shift.id;     
        ctrl.VolunteerShiftSignUp();
        System.AssertEquals(con.Id, ctrl.contactIdSignUp);
        System.Assert(ctrl.volunteerHoursIdSignUp != null);
        
        // pass cmp.Id as filter, verify only 2 jobs.
        // pass Show params with 0, verify values.
        pageRef = Page.VolunteersJobListing;
        pageRef.getParameters().put('ShowJobName', '0');
        pageRef.getParameters().put('ShowDescription', '0');
        pageRef.getParameters().put('ShowLocationAddress', '0');
        pageRef.getParameters().put('ShowLocationInfo', '0');
        pageRef.getParameters().put('ShowShifts', '0');
        pageRef.getParameters().put('ShowSkills', '0');
        pageRef.getParameters().put('campaignId', cmp.Id);
        Test.setCurrentPage(pageRef); 

        //instantiate the controller 
        ctrl = new VOL_CTRL_VolunteersJobListing();
        System.AssertEquals(2, ctrl.listVolunteerJobs.size());
        System.AssertEquals(cmp.Id, ctrl.campaignIdFilter);
        
        // create hours for new person, verify contact created
        ctrl.ClearVolunteerHoursIdSignUp();
        ctrl.contact.FirstName = 'New person';
        ctrl.contact.LastName = 'New person for my test';
        ctrl.contact.Email = 'newperson@volunteersjoblisting.com';
        ctrl.jobIdSignUp = job.id;
        ctrl.VolunteerShiftSignUp();
        System.Assert(ctrl.contactIdSignUp != null);
        System.Assert(ctrl.volunteerHoursIdSignUp != null);
        
    }
    
}