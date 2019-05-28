component {
	cfprocessingdirective( preserveCase=true );

	function init(
		required string apiKey
	,	required string apiSecret
	,	string apiUrl= "https://ssapi.shipstation.com"
	,	numeric timeout= 120
	,	boolean debug= false
	) {
		this.apiKey = arguments.apiKey;
		this.apiSecret = arguments.apiSecret;
		this.apiUrl = arguments.apiUrl;
		this.httpTimeOut = arguments.timeout;
		this.debug= arguments.debug;
		if ( structKeyExists( request, "debug" ) && request.debug == true ) {
			this.debug= request.debug;
		}
		// local to UTC to PST
		this.offSet = getTimeZoneInfo().utcTotalOffset - ( 7 * 60 * 60 );

		return this;
	}

	function debugLog( required input ) {
		if ( structKeyExists( request, "log" ) && isCustomFunction( request.log ) ) {
			if ( isSimpleValue( arguments.input ) ) {
				request.log( "shipstation: " & arguments.input );
			} else {
				request.log( "shipstation: (complex type)" );
				request.log( arguments.input );
			}
		} else if( this.debug ) {
			cftrace( text=( isSimpleValue( arguments.input ) ? arguments.input : "" ), var=arguments.input, category="shipstation", type="information" );
		}
		return;
	}

	struct function apiRequest( required string api, json= "", args= "" ) {
		var http = {};
		var dataKeys = 0;
		var item = "";
		var out = {
			success = false
		,	error = ""
		,	status = ""
		,	json = ""
		,	statusCode = 0
		,	response = ""
		,	verb = listFirst( arguments.api, " " )
		,	requestUrl = this.apiUrl & listRest( arguments.api, " " )
		};
		if ( isStruct( arguments.json ) ) {
			out.json = serializeJSON( arguments.json );
			out.json = reReplace( out.json, "[#chr(1)#-#chr(7)#|#chr(11)#|#chr(14)#-#chr(31)#]", "", "all" );
		} else if ( isSimpleValue( arguments.json ) && len( arguments.json ) ) {
			out.json = arguments.json;
		}
		//  copy args into url 
		if ( isStruct( arguments.args ) ) {
			out.requestUrl &= this.structToQueryString( arguments.args );
		}
		this.debugLog( out.requestUrl );
		if ( request.debug && request.dump ) {
			this.debugLog( out );
		}
		cftimer( type="debug", label="shipstation request" ) {
			cfhttp( result="http", method=out.verb, charset="UTF-8", url=out.requestUrl, throwOnError=false, password=this.apiSecret, timeOut=this.httpTimeOut, username=this.apiKey ) {
				if ( out.verb == "POST" || out.verb == "PUT" ) {
					cfhttpparam( name="Content-Type", type="header", value="application/json" );
					cfhttpparam( type="body", value=out.json );
				}
			}
		}
		// this.debugLog( http )
		out.response = toString( http.fileContent );
		if ( request.debug && request.dump ) {
			this.debugLog( out.response );
		}
		//  RESPONSE CODE ERRORS 
		if ( !structKeyExists( http, "responseHeader" ) || !structKeyExists( http.responseHeader, "Status_Code" ) || http.responseHeader.Status_Code == "" ) {
			out.statusCode = 500;
		} else {
			out.statusCode = http.responseHeader.Status_Code;
		}
		this.debugLog( out.statusCode );
		if ( left( out.statusCode, 1 ) == 4 || left( out.statusCode, 1 ) == 5 ) {
			out.success = false;
			out.error = "status code error: #out.statusCode#";
		} else if ( out.response == "Connection Timeout" || out.response == "Connection Failure" ) {
			out.error = out.response;
		} else if ( listFind( "200,201", http.responseHeader.Status_Code ) ) {
			out.success = true;
		}
		//  parse response 
		if ( len( out.response ) ) {
			try {
				out.response = deserializeJSON( replace( out.response, ':null', ':""', 'all' ) );
				if ( isStruct( out.response ) && structKeyExists( out.response, "ExceptionMessage" ) ) {
					out.success = false;
					out.error = out.response.ExceptionMessage;
				}
			} catch (any cfcatch) {
				out.error = "JSON Error: " & cfcatch.message;
			}
		}
		if ( len( out.error ) ) {
			out.success = false;
		}
		return out;
	}

	// ////////////////////////////////////////////////////////////
	// HELPER FUNCTIONS
	// ////////////////////////////////////////////////////////////

	function dateOffset(required string date) {
		if ( len( arguments.date ) && isDate( arguments.date ) ) {
			arguments.date = dateAdd( "s", this.offSet, arguments.date );
			arguments.date= dateTimeFormat( arguments.date, "yyyy-mm-dd HH:nn:ss" );
		} else {
			arguments.date= "";
		}
		return arguments.date;
	}

	string function structToQueryString( required struct stInput, boolean bEncode= true, string lExclude= "", string sDelims= "," ) {
		var sOutput = "";
		var sItem = "";
		var sValue = "";
		var amp = "?";
		for ( sItem in stInput ) {
			if ( !len( lExclude ) || !listFindNoCase( lExclude, sItem, sDelims ) ) {
				try {
					sValue = stInput[ sItem ];
					if ( len( sValue ) ) {
						if ( bEncode ) {
							sOutput &= amp & lCase( sItem ) & "=" & urlEncodedFormat( sValue );
						} else {
							sOutput &= amp & lCase( sItem ) & "=" & sValue;
						}
						amp = "&";
					}
				} catch (any cfcatch) {
				}
			}
		}
		return sOutput;
	}

	// ////////////////////////////////////////////////////////////
	// SHIPMENTS
	// ////////////////////////////////////////////////////////////

	function getShipment( required string shipmentId ) {
		var out = this.apiRequest( api= "GET /shipments", args= { shipmentId= arguments.shipmentId } );
		if ( out.success && arrayLen( out.response.shipments ) ) {
			out.response = out.response.shipments[ 1 ];
		} else {
			out.success = false;
			out.error &= " No shipments";
		}
		return out;
	}

	function getShipments(
		numeric page= 1
	,	numeric pageSize= 100
	,	string sortBy= "ShipDate"
	,	string sortDir= "ASC"
	,	numeric storeId
	,	string recipientName
	,	string recipientCountryCode
	,	string orderNumber
	,	numeric orderId
	,	string carrierCode
	,	string serviceCode
	,	string trackingNumber
	,	date createDateStart
	,	date createDateEnd
	,	date shipDateStart
	,	date shipDateEnd
	,	date voidDateStart
	,	date voidDateEnd
	,	boolean includeShipmentItems= false
	) {
		arguments.createDateStart= this.dateOffset( arguments.createDateStart ?: "" );
		arguments.createDateEnd= this.dateOffset( arguments.createDateEnd ?: "" );
		arguments.shipDateStart= this.dateOffset( arguments.shipDateStart ?: "" );
		arguments.shipDateEnd= this.dateOffset( arguments.shipDateEnd ?: "" );
		arguments.voidDateStart= this.dateOffset( arguments.voidDateStart ?: "" );
		arguments.voidDateEnd= this.dateOffset( arguments.voidDateEnd ?: "" );
		return this.apiRequest( api= "GET /shipments", args= arguments );
	}

	function getRates(
		required struct weight= { value=0, units="" }
	,	required struct dimensions= { length=0, width=0, height=0, units="" }
	,	required string carrierCode
	,	required string fromPostalCode
	,	required string toPostalCode
	,	required string toCountry
	,	string toState
	,	string toCity
	,	string serviceCode
	,	string packageCode
	,	string confirmation
	,	boolean residential= false
	) {
		return this.apiRequest( api= "GET /shipments/getrates", json= arguments );
	}

	// ////////////////////////////////////////////////////////////
	// ORDERS
	// ////////////////////////////////////////////////////////////

	function getOrder( required string orderId ) {
		return this.apiRequest( api= "GET /orders/#arguments.orderId#" );
	}

	function getOrders(
		numeric page= 1
	,	numeric pageSize= 100
	,	string sortBy= "OrderDate"
	,	string sortDir= "ASC"
	,	numeric storeId
	,	string orderNumber
	,	string orderStatus
	,	string customerName
	,	string itemKeyword
	,	date createDateStart
	,	date createDateEnd
	,	date modifyDateStart
	,	date modifyDateEnd
	,	date orderDateStart
	,	date orderDateEnd
	,	date paymentDateStart
	,	date paymentDateEnd
	) {
		arguments.createDateStart= this.dateOffset( arguments.createDateStart ?: "" );
		arguments.createDateEnd= this.dateOffset( arguments.createDateEnd ?: "" );
		arguments.modifyDateStart= this.dateOffset( arguments.modifyDateStart ?: "" );
		arguments.modifyDateEnd= this.dateOffset( arguments.modifyDateEnd ?: "" );
		arguments.orderDateStart= this.dateOffset( arguments.orderDateStart ?: "" );
		arguments.orderDateEnd= this.dateOffset( arguments.orderDateEnd ?: "" );
		arguments.paymentDateStart= this.dateOffset( arguments.paymentDateStart ?: "" );
		arguments.paymentDateEnd= this.dateOffset( arguments.paymentDateEnd ?: "" );
		return this.apiRequest( api= "GET /orders", args= arguments );
	}

	// orderStatus can be: awaiting_payment, awaiting_shipment, shipped, on_hold, cancelled
	function createOrder(
		required string orderNumber
	,	string orderKey
	,	required date orderDate
	,	required string orderStatus
	,	date paymentDate
	,	date shipByDate
	,	string customerUsername
	,	string customerEmail
	,	required struct billTo
	,	required struct shipTo
	,	struct items
	,	numeric amountPaid
	,	numeric taxAmount
	,	numeric shippingAmount
	,	string customerNotes
	,	string internalNotes
	,	boolean gift= false
	,	string giftMessage
	,	string paymentMethod
	,	string requestedShippingService
	,	string carrierCode
	,	string serviceCode
	,	string packageCode
	,	string confirmation
	,	string shipDate
	,	string weight
	,	struct dimensions
	,	struct insuranceOptions
	,	struct internationalOptions
	,	struct advancedOptions
	,	array tagIds
	) {
		arguments.orderDate= this.dateOffset( arguments.orderDate );
		arguments.paymentDate= this.dateOffset( arguments.paymentDate ?: "" );
		arguments.shipByDate= this.dateOffset( arguments.shipByDate ?: "" );
		arguments.shipDate= this.dateOffset( arguments.shipDate ?: "" );
		return this.apiRequest( api= "POST /orders/createorder", json= arguments );
	}

	// orderStatus can be: awaiting_payment, awaiting_shipment, shipped, on_hold, cancelled
	function updateOrder(
		required numeric orderId
	,	string orderNumber
	,	string orderKey
	,	date orderDate
	,	string orderStatus
	,	date paymentDate
	,	date shipByDate
	,	string customerUsername
	,	string customerEmail
	,	struct billTo
	,	struct shipTo
	,	struct items
	,	numeric amountPaid
	,	numeric taxAmount
	,	numeric shippingAmount
	,	string customerNotes
	,	string internalNotes
	,	boolean gift= false
	,	string giftMessage
	,	string paymentMethod
	,	string requestedShippingService
	,	string carrierCode
	,	string serviceCode
	,	string packageCode
	,	string confirmation
	,	string shipDate
	,	string weight
	,	struct dimensions
	,	struct insuranceOptions
	,	struct internationalOptions
	,	struct advancedOptions
	,	array tagIds
	) {
		arguments.orderDate= this.dateOffset( arguments.orderDate ?: "" );
		arguments.paymentDate= this.dateOffset( arguments.paymentDate ?: "" );
		arguments.shipByDate= this.dateOffset( arguments.shipByDate ?: "" );
		arguments.shipDate= this.dateOffset( arguments.shipDate ?: "" );
		return this.apiRequest( api= "POST /orders/createorder", json= arguments );
	}

	function shipOrder(
		required numeric orderId
	,	required string carrierCode
	,	date shipDate
	,	string trackingNumber
	,	boolean notifyCustomer= false
	,	boolean notifySalesChannel= false
	) {
		arguments.shipDate= this.dateOffset( arguments.shipDate ?: "" );
		return this.apiRequest( api= "POST /orders/markasshipped", json= arguments );
	}

	function deleteOrder( required numeric orderId, required numeric tagId ) {
		return this.apiRequest( api= "POST /orders/addtag", json= arguments );
	}

	function addTagToOrder( required numeric orderId, required numeric tagId ) {
		return this.apiRequest( api= "POST /orders/addtag", json= arguments );
	}

	function removeTagFromOrder( required numeric orderId, required numeric tagId ) {
		return this.apiRequest( api= "POST /orders/removetag", json= arguments );
	}

	function holdOrder( required numeric orderId, required date holdUntilDate ) {
		arguments.holdUntilDate= this.dateOffset( arguments.holdUntilDate );
		return this.apiRequest( api= "POST /orders/holduntil", json= arguments );
	}

	function unholdOrder( required numeric orderId ) {
		return this.apiRequest( api= "POST /orders/restorefromhold", json= arguments );
	}

	function assignUserToOrder( required numeric orderId, required numeric userId ) {
		return this.apiRequest( api= "POST /orders/assignuser", json= arguments );
	}

	function unassignUserFromOrder( required numeric orderId, required numeric userId ) {
		return this.apiRequest( api= "POST /orders/unassignuser", json= arguments );
	}

	// ////////////////////////////////////////////////////////////
	// WEB-HOOKS
	// ////////////////////////////////////////////////////////////

	function getWebhooks( numeric page= 1, numeric pageSize= 100 ) {
		return this.apiRequest( api= "GET /webhooks", args= arguments );
	}

	function subscribeToWebhook( 
		required string target_url
	,	required string event
	,	numeric store_id
	,	string friendly_name
	) {
		return this.apiRequest( api= "POST /webhooks/subscribe", json= arguments );
	}

	function removeWebhook( numeric id ) {
		return this.apiRequest( api= "DELETE /webhooks/#arguments.id#" );
	}

}
