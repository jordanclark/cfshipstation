component {
	// cfprocessingdirective( preserveCase=true );

	function init(
		required string apiKey
	,	required string apiSecret
	,	string apiUrl= "https://ssapi.shipstation.com"
	,	numeric throttle= 500
	,	numeric httpTimeOut= 120
	,	boolean debug
	) {
		arguments.debug = ( arguments.debug ?: request.debug ?: false );
		this.apiKey= arguments.apiKey;
		this.apiSecret= arguments.apiSecret;
		this.apiUrl= arguments.apiUrl;
		this.httpTimeOut= arguments.httpTimeOut;
		this.throttle= arguments.throttle;
		this.lastRequest= 0;
		this.debug= arguments.debug;
		// local to UTC to PST
		this.offSet= getTimeZoneInfo().utcTotalOffset - ( 7 * 60 * 60 );

		return this;
	}

	function getWait() {
		var wait= 0;
		if( this.throttle > 0 ) {
			this.lastRequest= max( this.lastRequest, server.shipstation_lastRequest ?: 0 );
			if( this.lastRequest > 0 ) {
				wait= max( this.throttle - ( getTickCount() - this.lastRequest ), 0 );
			}
		}
		return wait;
	}

	function setLastReq( numeric extra= 0 ) {
		if( this.throttle > 0 ) {
			this.lastRequest= max( getTickCount(), server.shipstation_lastRequest ?: 0 ) + arguments.extra;
			server.shipstation_lastRequest= this.lastRequest;
		}
	}

	function storeAPILimit( required numeric limit, required numeric remaining, required numeric reset ) {
		this.apiLimit= arguments.limit;
		this.apiRemaining= arguments.remaining;
		this.apiReset= arguments.reset;
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
			var info= ( isSimpleValue( arguments.input ) ? arguments.input : serializeJson( arguments.input ) );
			cftrace(
				var= "info"
			,	category= "shipstation"
			,	type= "information"
			);
		}
		return;
	}

	struct function cleanStruct( struct input ) {
		var out = {};
		for( key in arguments.input ) {
			value= arguments.input[ key ] ?: "";
			if( isNull( value ) ) {
				return;
			} else if( isSimpleValue( value ) ) {
				if( len( value ) ) {
					out[ key ] = value;
				}
			} else if( isArray( value ) ) {
				if( arrayLen( value ) ) {
					var tmp= this.cleanArray( value );
					if( arrayLen( tmp ) ) {
						out[ key ]= tmp;
					}
				}
			} else if( isStruct( value ) ) {
				if( !structIsEmpty( value ) ) {
					var tmp= this.cleanStruct( value );
					if( !structIsEmpty( tmp ) ) {
						out[ key ] = tmp;
					}
				}
			}
		}
		return out;
	}

	array function cleanArray( array input ) {
		var out = [];
		for( value in arguments.input ) {
			if( isNull( value ) ) {
				return;
			} else if( isSimpleValue( value ) ) {
				if( len( value ) ) {
					arrayAppend( out, value );
				}
			} else if( isArray( value ) ) {
				if( arrayLen( value ) ) {
					var tmp= this.cleanArray( value );
					if( arrayLen( tmp ) ) {
						arrayAppend( out, tmp );
					}
				}
			} else if( isStruct( value ) ) {
				if( !structIsEmpty( value ) ) {
					var tmp= this.cleanStruct( value );
					if( !structIsEmpty( tmp ) ) {
						arrayAppend( out, tmp );
					}
				}
			}
		}
		return out;
	}

	struct function apiRequest( required string api, json= "", args= "" ) {
		var http= {};
		var dataKeys= 0;
		var item= "";
		var out= {
			success= false
		,	error= ""
		,	status= ""
		,	json= ""
		,	statusCode= 0
		,	response= ""
		,	verb= listFirst( arguments.api, " " )
		,	requestUrl= this.apiUrl & listRest( arguments.api, " " )
		,	delay= 0
		};
		if ( isStruct( arguments.json ) ) {
			arguments.json= this.cleanStruct( arguments.json );
		//	arguments.json= structFilter( arguments.json, function( key, value ) {
		//		return !isNull( value ) || ;
		//	} );
			out.json= serializeJSON( arguments.json );
			out.json= reReplace( out.json, "[#chr(1)#-#chr(7)#|#chr(11)#|#chr(14)#-#chr(31)#]", "", "all" );
		} else if ( isArray( arguments.json ) ) {
			arguments.json= this.cleanArray( arguments.json );
			out.json= serializeJSON( arguments.json );
			out.json= reReplace( out.json, "[#chr(1)#-#chr(7)#|#chr(11)#|#chr(14)#-#chr(31)#]", "", "all" );
		} else if ( isSimpleValue( arguments.json ) && len( arguments.json ) ) {
			out.json= arguments.json;
		}
		// copy args into url 
		if ( isStruct( arguments.args ) ) {
			out.requestUrl &= this.structToQueryString( arguments.args );
		}
		this.debugLog( out.requestUrl );
		if( len( out.json ) ) {
			this.debugLog( out.json );
		}
		// throttle requests to keep it from going too fast
		out.wait= this.getWait();
		if( out.wait > 0 ) {
			this.debugLog( "Pausing for #out.wait#/ms" );
			sleep( out.wait );
		}
		// this.debugLog( out );
		cftimer( type="debug", label="shipstation request" ) {
			cfhttp( result="http", method=out.verb, url=out.requestUrl, username=this.apiKey, password=this.apiSecret, charset="UTF-8", throwOnError=false, timeOut=this.httpTimeOut ) {
				if ( out.verb == "POST" || out.verb == "PUT" ) {
					cfhttpparam( name="Content-Type", type="header", value="application/json" );
					cfhttpparam( type="body", value=out.json );
				}
			}
		}
		this.setLastReq();
		// this.debugLog( http )
		out.response= toString( http.fileContent );
		out.headers= http.responseHeader;
		// this.debugLog( out.response );
		out.statusCode= http.responseHeader.Status_Code ?: 500;
		if( out.statusCode == '429' ) {
			var delay= val( out.headers[ "X-Rate-Limit-Reset" ] ) * 1000;
			out.error= "too many requests, quote resets in #delay#/ms";
			this.setLastReq( delay );
		} else if ( left( out.statusCode, 1 ) == 4 || left( out.statusCode, 1 ) == 5 ) {
			out.error= "status code error: #out.statusCode#";
		} else if ( out.response == "Connection Timeout" || out.response == "Connection Failure" ) {
			out.error= out.response;
		} else if ( left( out.statusCode, 1 ) == 2 ) {
			out.success= true;
		}
		if( out.headers[ "X-Rate-Limit-Limit" ] ?: 0 > 0 ) {
			this.storeAPILimit( out.headers[ "X-Rate-Limit-Limit" ], out.headers[ "X-Rate-Limit-Remaining" ], out.headers[ "X-Rate-Limit-Reset" ] );
		}
		// parse response 
		if ( out.success && len( out.response ) ) {
			try {
				out.response= deserializeJSON( replace( out.response, ':null', ':""', 'all' ) );
				if ( isStruct( out.response ) && structKeyExists( out.response, "ExceptionMessage" ) ) {
					out.success= false;
					out.error= out.response.ExceptionMessage;
				}
			} catch (any cfcatch) {
				out.error= "JSON Error: " & (cfcatch.message?:"No catch message") & " " & (cfcatch.detail?:"No catch detail");
			}
		} else if ( !out.success && len( out.response ) ) {
			out.error &= " " & out.response;
		}
		if ( len( out.error ) ) {
			out.success= false;
		}
		this.debugLog( out.statusCode & " " & out.error );
		return out;
	}

	// ////////////////////////////////////////////////////////////
	// HELPER FUNCTIONS
	// ////////////////////////////////////////////////////////////

	function dateOffset(required string date) {
		if ( len( arguments.date ) && isDate( arguments.date ) ) {
			arguments.date= dateAdd( "s", this.offSet, arguments.date );
			arguments.date= dateTimeFormat( arguments.date, "yyyy-mm-dd HH:nn:ss" );
		} else {
			arguments.date= "";
		}
		return arguments.date;
	}

	string function structToQueryString( required struct stInput, boolean bEncode= true ) {
		var out= "";
		var amp= "?";
		for ( var sItem in stInput ) {
			var sValue= stInput[ sItem ] ?: "";
			if ( len( sValue ) ) {
				out &= amp & lCase( sItem ) & "=" & urlEncodedFormat( sValue );
				amp= "&";
			}
		}
		return out;
	}

	// ////////////////////////////////////////////////////////////
	// SHIPMENTS
	// ////////////////////////////////////////////////////////////

	function getShipment( required string shipmentId ) {
		var out= this.apiRequest( api= "GET /shipments", args= { shipmentId= arguments.shipmentId } );
		if ( out.success && arrayLen( out.response.shipments ) ) {
			out.response= out.response.shipments[ 1 ];
		} else {
			out.success= false;
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
	,	numeric batchId
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
		return this.apiRequest( api= "POST /shipments/getrates", json= arguments );
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
	,	array items
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
		required string orderKey
	,	string orderNumber
	,	date orderDate
	,	string orderStatus
	,	date paymentDate
	,	date shipByDate
	,	string customerUsername
	,	string customerEmail
	,	struct billTo
	,	struct shipTo
	,	array items
	,	numeric amountPaid
	,	numeric taxAmount
	,	numeric shippingAmount
	,	string customerNotes
	,	string internalNotes
	,	boolean gift
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

	function addOrderToBatch(
		required array batch
	,	string orderKey
	,	string orderNumber
	,	date orderDate
	,	string orderStatus
	,	date paymentDate
	,	date shipByDate
	,	string customerUsername
	,	string customerEmail
	,	struct billTo
	,	struct shipTo
	,	array items= []
	,	numeric amountPaid
	,	numeric taxAmount
	,	numeric shippingAmount
	,	string customerNotes
	,	string internalNotes
	,	boolean gift
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
		var b= arguments.batch;
		structDelete( arguments, "batch" );
		arrayAppend( b, arguments );
		return b;
	}

	// orderStatus can be: awaiting_payment, awaiting_shipment, shipped, on_hold, cancelled
	function updateBatchOrder( required array batch ) {
		return this.apiRequest( api= "POST /orders/createorder", json= arguments.batch );
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

	function deleteOrder( required numeric orderId ) {
		return this.apiRequest( api= "DELETE /orders/#arguments.orderId#", json= arguments );
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
