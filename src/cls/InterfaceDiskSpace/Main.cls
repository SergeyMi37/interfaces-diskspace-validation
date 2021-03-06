/// A framework to test for disk space consumption for Ensemble interfaces.
/// <br><br>
/// It has a dual purpose -
/// <br>
/// To aid in estimating the required disk space interfaces will consume (both database file growth and journal files)
/// <br>
/// As well as verifying the Ensemble Purge mechanism will indeed clean out all the interfaces' related data
/// <br><br>
/// The basic minimum steps for testing are:
/// <ul>
/// <li><method>PreTestRun</method> - This method will setup the stage for the testing and counting of data. This will also provide a <code>Run ID</code> to use during the next steps</li>
/// <li>Run the test - This could be by manually running whatever Production and operating the relevant interfaces.<br>If there is an automated test you can use the <method>RunTest</method> method - This method will run the given user-provided method for an automated test</li>
/// <li><method>TestSummary</method> - This method collects the data post the actual test run</li>
/// <li><method>PurgeTest</method> - This method runs the Purge and will compare what globals might be left-over</li>
/// <li>Examine the collected Data - see the space accumulated in the database file and journal to determine how much space will be needed for the planned volume of the interfaces. See if the Purge left-over any data that should have been deleted
/// <br>Can optionally use the <method>Report</method> method to view the data collected</li>
/// </ul>
/// Optionally instead of running each of these steps manually, assuming there is an automated test method, for convenience there is a <method>RunFullFlow</method> method that can run all of the steps, one after the other
/// <br><br>
/// The data collected is stored in two tables: <class>InterfaceDiskSpace.DataLog</class> and <class>InterfaceDiskSpace.DataCapture</class>
/// <br>
/// DataLog is simply the reference to 3 "data captures":
/// <ol>
/// <li>BeforeRunData</li>
/// <li>AfterRunData</li>
/// <li>AfterPurgeData</li>
/// </ol>
/// Each of the "data captures" has the following data:
/// <ul>
/// <li>CaptureTime - the time the capture was taken</li>
/// <li>DBSize - the database size used</li>
/// <li>JournalSize - the size of the journal file</li>
/// <li>JournalSpaceUsed - the total size of the journal records</li>
/// </ul>
/// Sample capture data:
/// <br><br>
/// <table border="1">
/// <tr><td>ID</td><td>CaptureTime</td><td>DBSize</td><td>JournalSize</td><td>JournalSpaceUsed</td></tr>
/// <tr><td>1</td><td>2016-05-16 11:17:28</td><td>61.6</td><td>1048576</td><td>300644</td></tr>
/// <tr><td>2</td><td>2016-05-16 11:20:17</td><td>61.8</td><td>1048576</td><td>296684</td></tr>
/// </table>
/// <br>
/// It also includes two arrays of specific global data usage sizes - the global sizes and the Journal sizes:
/// <ul>
/// <li>GlobalSizes</li>
/// <li>JournalProfileSizes</li>
/// </ul>
/// The key of these arrays is the global name, as well as, where possible, the class name related to this global.
/// <br>   E.g. <code>MyPackage.MyClassD<font style="background-color:yellow;">|</font>MyPackage.MyClass.cls</code>
/// <br><br>
/// There is a test Production for testing purposes of this framework - under package <class>InterfaceDiskSpace.Test</class>
Class InterfaceDiskSpace.Main Extends %RegisteredObject
{

/// To run before the actual test:
/// <ol>
/// 	<li>Clean database</li>
/// 	<li>Log Sizes</li>
/// 	<li>Switch Journal</li>
/// 	</ol>
/// <br>
/// Parameters:
/// <ol>
/// <li><b>RunId</b> - and output parameter returned by reference, referring to the dataLog created. To be used in the calls to the next methods</li>
/// <li><b>CleanOption</b> - How to "clean" the current data before the test run:
/// 		<ul>
/// 		<li>P - Purge - Use the Ensemble Purge mechanism (with the following options: 0 Days to keep, Do not keep integrity, include bodies</li>
/// 		<li>K - Kill - Run a globals list query and kill all globals that are not: System globals, or start with: Ens, Cache or DeepSee. See also the <code>MaskNotToClean</code> where a user can add further globals not to kill
/// 		<br><b><font color="red">CAUTION - this option should be used very carefully as it could potentially delete/kill valuable data. Test very carefully before use in system with important data</font></b>
/// 		<br>
/// 			It could be useful in case the Purge indeed does not remove all the data and you want to make sure everything is wiped out - the problem is that "everything" might be too far fetched than desired</li>		
/// 		<li>U - User-defined - Provide a user-defined class name and method name that will perform the cleaning</li>
/// 		<li>N - None - do not perform any cleaning</li>
/// 		</ul>
/// </li>
/// <li><b>MaskNotToClean</b> - Per previous parameter - an option to add further global masks not to kill.
/// 	For example: 'MyPackage* <br>
/// For not including globals starting with MyPackage
/// </li>
/// <li><b>PromptBeforeCleanLevel</b> - Whether and where to prompt before cleaning data
/// 		<ul>
/// 		<li>E - Each - Relevant when using the "K[ill]" option for cleaning - will prompt before issuing the KILL command for each global</li>
/// 		<li>A - All - Will ask before cleaning the data (Purge, or Kill, or User-defined)</li>
/// 		<li>N - None - Do not ask before cleaning</li>
/// 		</ul>
/// </li>
/// <li><b>UserCleanClass</b> - the class name of the user-defined method to perform the data cleaning (instead of Purging or Killing, see "U" value above in the CleanOption parameter</li>
/// <li><b>UserCleanMethod</b> - the method name of the above mentioned clean method</li>
/// <li><b>StopProduction</b> - whether to stop the Production before the Pre-Test steps</li>
/// <li><b>CleanProduction</b> - whether to run the CleanProduction method before performing the rest of the steps [Note CleanProduction should be run only in a dev/test environment and NOT in an production environment</li>
/// <li><b>Verbose</b> - whether to output information during the process</li>
/// </ol>
ClassMethod PreTestRun(Output RunId As %String = "", CleanOption As %String = "P", MaskNotToClean As %String = "", PromptBeforeCleanLevel As %String = "E", UserCleanClass As %String = "", UserCleanMethod As %String = "", StopProduction As %Boolean = 1, CleanProduction As %Boolean = 1, Verbose As %Boolean = 1) As %Status
{
	#dim ex As %Exception.SystemException
	#dim status As %Status = $$$OK
	
	Try {
		
		// instantiate a new object for logging data for this test run
		Set dataLog = ##class(InterfaceDiskSpace.DataLog).%New()
		
		// Stop the production, if desired
		If StopProduction {
			If Verbose Write !,"Stopping Production...",!
			Set status = ##class(Ens.Director).StopProduction()	
			If $$$ISERR(status) Quit
		}
		
		// Run "Clean Production" if desired to avoid any "leftover" suspended messages and such
		If CleanProduction {
			If Verbose Write !,"Cleaning Production...",!
			Set status = ##class(Ens.Director).CleanProduction()	
			If $$$ISERR(status) Quit
		}
		
		// Ask for conformation for deleting data
		If PromptBeforeCleanLevel'="N" {
			Write "Confirm cleaning data <y/n>?",!
			Read confirm
			If (confirm '= "y") && (confirm '= "Y") {
				Quit	
			}
		}
		
		// Use Ensemble Purge [Keep 0 days, do NOT keep integrity and include also message bodies
		If CleanOption = "P" {
			Kill deleteCounts
			Set deleteCounts = ""
			If Verbose Write !,"Purging...",!
			Set status = ##class(Ens.Purge).PurgeAll(.deleteCounts,
														/* Days to keep*/ 0,
														/* Keep Integrity */ 0,
														/* Include Bodies */ 1)
			If Verbose {
				Write !,"Purged: ",!
				Zwrite deleteCounts
				Write !
			}
			
		// Kill all non-system/Ensemble globals	
		// ***************************
		// CAUTION - This option should be used with great caution as it could potentially kill valuable data											
		// ***************************
		} ElseIf CleanOption = "K" {
			#dim result As %SQL.StatementResult
			 Set stat = ##class(%SQL.Statement).%New()
			 
			 // Use the Global Query Namespace global list
			 Set status = stat.%PrepareClassQuery("%SYS.GlobalQuery","NameSpaceList")
			 
			 If $$$ISERR(status) Quit
			 
			 // Do not delete globals that start with Ens or Cache or DeepSee or the globals ERRORS or Sources
			 Set mask = "*,'Ens*,'Cache*,'DeepSee*,'ERRORS,'Sources"
			 
			 // Optionally add further masks not to delete
			 If MaskNotToClean '= "" {
				Set mask = mask _ "," _ MaskNotToClean	 
			 }
			 Set result = stat.%Execute(,mask) ///* Namespace */ $system.SYS.NameSpace(),/* Mask */ "",/* System Globals */ 0)
			 
			 
			 If Verbose Write "Killing Globals...",!
			 While result.%Next() {
				Set globalName = result.%Get("Name")
				If PromptBeforeCleanLevel="E" {
					Write "Confirm Killing global ",globalName," <y/n>?",!
					Read confirm
					If (confirm '= "y") && (confirm '= "Y") {
						Continue	
					}
				}
				Set globalName="^"_globalName
				Write !,"about to kill "_globalName,!
				Kill @globalName
					 
			 }
			 
			 // Before skipped all Ens* globals, so now need to handle Ens.Message* globals
			 //		e.g. Header and Body globals
			 set mask = "Ens.Message*"
			 Set result = stat.%Execute(,mask) ///* Namespace */ $system.SYS.NameSpace(),/* Mask */ "",/* System Globals */ 0)
			 
			 
			 
			 While result.%Next() {
				Set globalName = result.%Get("Name")
				If PromptBeforeCleanLevel="E" {
					Write !,"Confirm Killing global ",globalName," <y/n>?",!
					Read confirm
					If (confirm '= "y") && (confirm '= "Y") {
						Continue	
					}
				}
				Set globalName="^"_globalName
				Write !,"about to kill "_globalName
				Kill @globalName
					 
			 }
			 
			 
		// clean/delete existing data by calling user-supplied method 
		} ElseIf CleanOption = "U" {
			If Verbose Write "User-defined cleaning...",!
			// First check if the method exists
			If '##class(%Dictionary.MethodDefinition).%ExistsId(UserCleanClass_"||"_UserCleanMethod) {
				Set status = $$$ERROR("No class or method")	
				Quit
			} 
			Set status = $classmethod(UserCleanClass,UserCleanMethod)
		}
		
		// Now switch the journal so we start with a clean journal
		If Verbose Write "Switching Journal...",!
		 // Switch the Journal file
		Set status = ##class(%SYS.Journal.System).SwitchFile()
		If $$$ISERR(status) Quit
		
		
		// Go off and capture data to log what we start off with
		If Verbose Write "Capturing data...",!
		Set status = ..CaptureData(.captureData)
		
		// Update the "Before Run" data of our log entity	 
		Set dataLog.BeforeRunData = captureData
				 
		Set status = dataLog.%Save()
		 
		If $$$ISERR(status) Quit
		 
		// Return the log's entity ID (be reference) as we'll need it later on during the run for updating more data and finally reporting the results
		Set RunId = dataLog.%Id()
		 
		 
		
		 
		
	} Catch ex {
		Set status = ex.AsStatus()	
	}
	Quit status
}

/// Runs a user-defined method to perform the Production test and data generation
/// 	<br>
/// This method could be a UnitTest or any other user-defined method
/// <br>
/// The <b><code>StartProduction</code></b> argument determines whether a Production Start is required before running the test method. 
/// For example if using Ensemble UnitTesting this is not required because the UnitTest framework takes care of it by itself
ClassMethod RunTest(UserTestClass As %String = "", UserTestMethod As %String = "", StartProduction As %Boolean = 1) As %Status
{
	#dim ex As %Exception.SystemException
	#dim status As %Status = $$$OK
	Try {
		
		// If required start the production first before running th test
		If StartProduction {
			Set status = ##class(Ens.Director).StartProduction()	
			If $$$ISERR(status) Quit
		}
		// Check first if the method provided exists
		If '##class(%Dictionary.CompiledMethod).%ExistsId(UserTestClass_"||"_UserTestMethod) {
			Set status = $$$ERROR("No class or method")	
			Quit
		} 
		Set status = $classmethod(UserTestClass,UserTestMethod)
	} Catch ex {
		Set status = ex.AsStatus()	
	}
	Quit status
}

/// Summarizes the data (captures data) regarding the test run (a "Post" test method)
/// <br> 
/// Provide a test run Id (returned by reference from the <method>PreTestRun</method> method)
ClassMethod TestSummary(RunId As %String = "") As %Status
{
	#dim ex As %Exception.SystemException
	#dim status As %Status = $$$OK
	Try {
		
		//Open the dataLog - using the runID previously returned when running the test
		Set dataLog = ##class(InterfaceDiskSpace.DataLog).%OpenId(RunId,,.status)
		
		If $$$ISERR(status) Quit
		
		// Capture the data as it is after the test, this will allow for calculations to estimate sizing for the testing interfaces
		// This time include also Journal Profiling data
		Set status = ..CaptureData(.captureData,1 /* include journal data */)
		
		// Update the data log entity with the "after run" data
		 Set dataLog.AfterRunData = captureData
		 
		 Set status = dataLog.%Save()
		 
		 If $$$ISERR(status) Quit
	} Catch ex {
		Set status = ex.AsStatus()	
	}
	Quit status
}

/// Runs the Purge after the test run and captures relevant data
/// <br>
/// It uses these parameters:
/// <ul>
/// <li>Day to keep = 0</li>
/// <li>Keep Integrity = 0</li>
/// <li>Include Bodies = 1</li>
/// </ul>
ClassMethod PurgeTest(RunId As %String = "", Verbose As %Boolean = 0) As %Status
{
	#dim ex As %Exception.SystemException
	#dim status As %Status = $$$OK
	Try {
		
		//Open the dataLog
		Set dataLog = ##class(InterfaceDiskSpace.DataLog).%OpenId(RunId,,.status)
		
		If $$$ISERR(status) Quit
		
		Kill deleteCounts
		Set deleteCounts = ""
		Set status = ##class(Ens.Purge).PurgeAll(.deleteCounts,
														/* Days to keep*/ 0,
														/* Keep Integrity */ 0,
														/* Include Bodies */ 1)
		
		If Verbose {
				Write !,!,"Purged: ",!
				Zwrite deleteCounts
				Write !
			}
		
		// collect data after the purge this will allow to determine if we are "leaking" undesired data after the purge which does not get deleted
		Set status = ..CaptureData(.captureData)
		
		Set dataLog.AfterPurgeData = captureData
		 
		Set status = dataLog.%Save()
		 
		If $$$ISERR(status) Quit
	} Catch ex {
		Set status = ex.AsStatus()	
	}
	Quit status
}

/// Reports the data collected (where possible adds to the global name also the related class name)
/// <br> for example:
/// <br>
/// <code>
///  
/// 
/// <br>Data Usage Report
/// <br>===========================
/// <br> 
/// <br>Database file size used: .1
/// <br>Journal file size used: 0
/// <br>Journal space used: 296684
/// <br> 
/// <br>Globals growth
/// <br>----------------------
/// <table>
/// <tr><td>Ens.MessageHeaderD</td><td></td><td>.015</td></tr>
/// <tr><td>Ens.MessageHeaderI</td><td></td><td>.003</td></tr>
/// <tr><td>Ens.Rule.LogD</td><td></td><td>.011</td></tr>
/// <tr><td>Ens.Rule.LogI</td><td></td><td>.002</td></tr>
/// <tr><td>Ens.Util.LogD</td><td></td><td>.002</td></tr>
/// <tr><td>InterfaceDiskSpaceD85F.RecordD</td><td>InterfaceDiskSpace.Test.RM.Record.Record.cls</td><td>.015</td></tr>
/// </table>
/// <br> 
/// <br>Journal Profile
/// <br>----------------------
/// <table>
/// <tr><td>Ens.BusinessProcessD</td><td></td><td>73804</td></tr>
/// <tr><td>Ens.BusinessProcessI</td><td></td><td>24780</td></tr>
/// <tr><td>Ens.JobRequest</td><td></td><td>16</td></tr>
/// <tr><td>Ens.JobStatus</td><td></td><td>48</td></tr>
/// <tr><td>Ens.MessageHeaderD</td><td></td><td>20056</td></tr>
/// <tr><td>Ens.MessageHeaderI</td><td></td><td>66464</td></tr>
/// <tr><td>Ens.Queue</td><td></td><td>440</td></tr>
/// <tr><td>Ens.Rule.LogD</td><td></td><td>20912</td></tr>
/// <tr><td>Ens.Rule.LogI</td><td></td><td>26512</td></tr>
/// <tr><td>Ens.Runtime</td><td></td><td>13568</td></tr>
/// <tr><td>Ens.Suspended</td><td></td><td>80</td></tr>
/// <tr><td>Ens.Util.LogD</td><td></td><td>4204</td></tr>
/// <tr><td>Ens.Util.LogI</td><td></td><td>4232</td></tr>
/// <tr><td>InterfaceDiskSpaceD85F.RecordD</td><td>InterfaceDiskSpace.Test.RM.Record.Record.cls</td><td>22588</td></tr>
/// </table>
/// <br> 
/// <br>Globals remaining after purge
/// <br>----------------------
/// <br> 
/// </code>
ClassMethod Report(RunId As %String = "") As %Status
{
	#dim ex As %Exception.SystemException
	#dim status As %Status = $$$OK
	Try {
		
		//Open the dataLog
		Set dataLog = ##class(InterfaceDiskSpace.DataLog).%OpenId(RunId,,.status)
		If $$$ISERR(status) Quit
		
		Write !,!,"Data Usage Report",!
		Write "===========================",!
		// Calculate the size used by the subtracting the size before the test from the one after
		Set DBSpaceUsed = dataLog.AfterRunData.DBSize-dataLog.BeforeRunData.DBSize
		Write !,"Database file size used: ",DBSpaceUsed,!
		
		// Similar to the DB Size
		Set JournalSizeUsed = dataLog.AfterRunData.JournalSize-dataLog.BeforeRunData.JournalSize
		Write "Journal file size used: ",JournalSizeUsed,!
		
		
		Write "Journal space used: ",dataLog.AfterRunData.JournalSpaceUsed,!
		
		
		// Now on to global level comparison
		
		Write !,"Globals growth",!
		Write "----------------------",!
		Set globalName=""
		Set globalRef=""
		// We'll loop over the globals and calculate the difference in each between before after and before the test
		Set sizeAfter = dataLog.AfterRunData.GlobalSizes.GetNext(.globalRef)
		
		// We want to skip globals that are related to this data capture, as well as UnitTest [same behavior also later]
		While globalRef'="" {
			Set globalName = $Piece(globalRef,"|",1)
			Set className = $Piece(globalRef,"|",2)
			If ((globalName="InterfaceDiskS13C5.DataCaptureD") ||
				(globalName="InterfaceDiskSpace.DataLogD") ||
				 (globalName="UnitTest.Result") ||
				 (globalName="UnitTest.ResultI")) {
					 // Skip...
				 } Else {
				Set sizeBefore = dataLog.BeforeRunData.GlobalSizes.GetAt(globalRef)	
				
				Set globalSizeUsed = sizeAfter-sizeBefore
				If globalSizeUsed>0 {
					Write globalName,?35,className,?85,globalSizeUsed,!
				}
				 }
			Set sizeAfter = dataLog.AfterRunData.GlobalSizes.GetNext(.globalRef)
		}
		
		Write !,"Journal Profile",!
		Write "----------------------",!
		Set globalName=""
		Set globalRef=""
		// loop over the global entries
		Set journalGlobalSize = dataLog.AfterRunData.JournalProfileSizes.GetNext(.globalRef)
		
		While globalRef'="" {
			Set globalName = $Piece(globalRef,"|",1)
			Set className = $Piece(globalRef,"|",2)
			If ((globalName="InterfaceDiskS13C5.DataCaptureD") ||
				(globalName="InterfaceDiskSpace.DataLogD") ||
				 (globalName="UnitTest.Result") ||
				 (globalName="UnitTest.ResultI") || 
				 (globalName="oddDEF") || 
				 (globalName="rINDEXCLASS")) {
					 // Skip...
				 } Else {
					Write globalName,?35,className,?85,journalGlobalSize,!
				
				 }
			Set journalGlobalSize = dataLog.AfterRunData.JournalProfileSizes.GetNext(.globalRef)
		}
		
		// Later - check what happened after purge - which globals did not return to original size?
		
		Write !,"Globals remaining after purge",!
		Write "----------------------",!
		Set globalRef=""
		Set sizeAfter = dataLog.AfterPurgeData.GlobalSizes.GetNext(.globalRef)
		While globalRef'="" {
			Set globalName = $Piece(globalRef,"|",1)
			Set className = $Piece(globalRef,"|",2)
			If ((globalName="InterfaceDiskS13C5.DataCaptureD") ||
				(globalName="InterfaceDiskSpace.DataLogD") ||
				 (globalName="UnitTest.Result") ||
				 (globalName="UnitTest.ResultI")) {
					 // Skip...
				 } Else {
				Set sizeBefore = dataLog.BeforeRunData.GlobalSizes.GetAt(globalRef)	
				
				Set globalSizeUsed = sizeAfter-sizeBefore
				If globalSizeUsed>0 {
					Write globalName,?35,className,?85,globalSizeUsed,!
				}
				 }
			Set sizeAfter = dataLog.AfterPurgeData.GlobalSizes.GetNext(.globalRef)
		}
		
		/// Check if can get actual Journal size used.
		
		
	} Catch ex {
		Set status = ex.AsStatus()	
	}
	Quit status
}

/// Internal method used by the class to find the class (aka Extent) name used by a global
/// <br>
/// 
ClassMethod GetClassName(globalName As %String = "", Output className As %String = "") As %Status [ Private ]
{
	#dim ex As %Exception.SystemException
	#dim status As %Status = $$$OK
	
	Try { 
		#dim %sqlcontext As %Library.ProcedureContext = ""
		// Find extent name (class names) using this global
		Set className = ""
		
		Do ##class(%ExtentMgr.Util).GlobalUses("^"_globalName)
		
		If $IsObject(%sqlcontext) {
			If %sqlcontext.%Next() {
				Set className = %sqlcontext.%Get("UsedByExtent")
			}
		}
	} Catch ex {
		Set status = ex.AsStatus()	
	}
	Quit status
}

/// Internal method used by the class to capture and log the data
/// <br>
/// It collects the following info:
/// <ul>
/// <li>Size of database (actual size used)</li>
/// <li>Sizes of all globals</li>
/// <li>Size of journal</li>
/// <li>Journal Profile </li>
/// </ul>
ClassMethod CaptureData(Output captureData As InterfaceDiskSpace.DataCapture = "", includeJournalProfile As %Boolean = 0) As %Status [ Private ]
{
	#dim ex As %Exception.SystemException
	#dim status As %Status = $$$OK
	Try {
		
		// instantiate a new data capture object
		Set captureData = ##class(InterfaceDiskSpace.DataCapture).%New()
		
		Set TS = $ZDateTime($Horolog,3)
		Set captureData.CaptureTime = TS
		
		
		// Now just count and register
		 Set stat = ##class(%SQL.Statement).%New()
		 
		 Set status = stat.%PrepareClassQuery("%SYS.GlobalQuery","Size")
		 
		 If $$$ISERR(status) Quit
		 Set directory = ##class(%Library.File).NormalizeDirectory("")
		 Set result = stat.%Execute(directory) 
		 
			 
		 
		 
		 While result.%Next() {
			Set globalName = result.%Get("Name")
			Set globalSize = result.%Get("Used MB")
			
			// Find extent name (class names) using this global
			Set status = ..GetClassName(globalName,.className)
			If $$$ISERR(status) Quit
			
			Set globalRef = globalName _ "|" _ className
			Do captureData.GlobalSizes.SetAt(globalSize,globalRef)
			// Log Global Size
					 
		 }		
		If $$$ISERR(status) Quit
		
		
		//Need to move to %SYS namespace in order to run the Freespace query
		Set currentNS = $system.SYS.NameSpace()
		
		
		ZNSpace "%SYS"
		
		Set NSConfig = ##class(Config.Namespaces).Open(currentNS)
		Set DBName = NSConfig.Globals
		
		Set stat = ##class(%SQL.Statement).%New()
		 
		 Set status = stat.%PrepareClassQuery("SYS.Database","FreeSpace")
		 
		 
		 If $$$ISERR(status) Quit
		 
		 Set result = stat.%Execute(DBName) 
		 
			 
		 Set actualSize = ""
		 If result.%Next() {
			 // To get the used size need to take full size and available and substruct
			Set size = result.%Get("SizeInt")
			Set available = result.%Get("AvailableNum")
			
			Set actualSize = size - available
					 
		 }		
		Set result=""
		ZNSpace currentNS
		
		Set captureData.DBSize = actualSize
		
		// Now check the journal file size
		Set result = ##class(%ResultSet).%New()
		 Set result.ClassName="%SYS.Journal.File"
		 Set result.QueryName="ByTimeReverseOrder"
		 
		 
		 Set status = result.Execute() 
		 If $$$ISERR(status) Quit
		 
		 Set journalSize = ""
		 If result.Next() {
			Set journalSize = result.Get("Size")
			Set journalFileName = result.Get("Name")
								 
		 }	
		 
		 Set captureData.JournalSize = journalSize
		 ZNSpace currentNS
		 
		 Set totalJournalUSedSpace = 0
		 
		 // Review the Journal Profile info
		 If includeJournalProfile {
			
			Set status = ##class(%CSP.UI.System.OpenJournalPane).GetJournalProfile(journalFileName,.profile)	 
			
			/*
			The profile array returned has the following structure -
			
			profile("OTHER")=261992
			profile("c:\intersystems\ensemble20153\mgr\","%SYS")=328
			profile("c:\intersystems\ensemble20153\mgr\","%Studio.DocumentHistory")=828
			profile("c:\intersystems\ensemble20153\mgr\","SYS")=160
			profile("c:\intersystems\ensemble20153\mgr\cacheaudit\","CacheAuditD")=1528
			profile("c:\intersystems\ensemble20153\mgr\ensdemo\","Ens.BusinessProcessD")=73804
			profile("c:\intersystems\ensemble20153\mgr\ensdemo\","Ens.BusinessProcessI")=24780
			profile("c:\intersystems\ensemble20153\mgr\ensdemo\","Ens.JobRequest")=16
			profile("c:\intersystems\ensemble20153\mgr\ensdemo\","Ens.JobStatus")=48
			...
			
			
			*/
			If $$$ISERR(status) Quit
			Set directory = $ZConvert(directory,"L")
			Set database=""
			Set database=$Order(profile(database))
			While database'="" {
			
				If database=directory {
					Set globalJournalName = ""
					Set globalJournalName=$Order(profile(database,globalJournalName))
					
					
					
					While globalJournalName'="" {
						Set spaceUsed = profile(database,globalJournalName)
						
						// Find extent name (class names) using this global
						Set journalClassName = ""
						Set status = ..GetClassName(globalJournalName,.journalClassName)
						If $$$ISERR(status) Quit
			
						Set journalGlobalRef = globalJournalName _ "|" _ journalClassName
						
						Do captureData.JournalProfileSizes.SetAt(spaceUsed,journalGlobalRef)
						Set totalJournalUSedSpace = totalJournalUSedSpace + spaceUsed
						
						Set globalJournalName=$Order(profile(database,globalJournalName))
					}
				}
				Set database=$Order(profile(database))
			}
			
			Set captureData.JournalSpaceUsed = totalJournalUSedSpace
		 }
		
	} Catch ex {
		Set status = ex.AsStatus()	
	}
	Quit status
}

/// A "Meta" method to call other methods in sequence of operations
/// <br>for example:
/// <example>Do ##class(InterfaceDiskSpace.Main).RunFullFlow("P" /* Clean Option - Purge*/,"" /* Mask not Kill */, "E" /* Prompt before clean level - Each */, "" /* User clean class */, "" /* User clean method */, 1 /* Stop Production */, 1 /* Clean Production */, 1 /* Verbose */,	 "InterfaceDiskSpace.Test.ProdUnitTest" /* User test class */, "Run" /* User test method */, 0 /* Start Production */)</example>
ClassMethod RunFullFlow(CleanOption As %String = "P", MaskNotToClean As %String = "", PromptBeforeCleanLevel As %String = "E", UserCleanClass As %String = "", UserCleanMethod As %String = "", StopProduction As %Boolean = 1, CleanProduction As %Boolean = 1, Verbose As %Boolean = 1, UserTestClass As %String = "", UserTestMethod As %String = "", StartProduction As %Boolean = 1) As %Status
{
	Set status = ..PreTestRun(.runId,CleanOption,MaskNotToClean,PromptBeforeCleanLevel,UserCleanClass,UserCleanMethod,StopProduction,CleanProduction,Verbose)
	If $$$ISERR(status) Quit status
	
	Set status=..RunTest(UserTestClass,UserTestMethod,StartProduction)
	If $$$ISERR(status) Quit status
	
	Set status = ..TestSummary(runId)
	If $$$ISERR(status) Quit status
	
	Set status = ..PurgeTest(runId,Verbose)
	If $$$ISERR(status) Quit status
	
	Set status = ..Report(runId)
	Quit status
}

}
