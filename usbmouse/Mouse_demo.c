/*	Mouse_demo.c
	Class-compliant USB mouse driver for PIC32
	A trimmed-down version of the "USB Host - HID Mouse" demo program
	from the Microchip Application Libraries, retreived June 2010 from
	the Microchip website.
	
*/
/*  Matthew Watkins
	Fall 2010
  	Simplified 25 October 2011 David_Harris & Karl_Wang@hmc.edu
*/

/******************************************************************************

    USB Mouse Host Application Demo

Description:
    This file contains the basic USB Mouse application demo. Purpose of the demo
    is to demonstrate the capability of HID host . Any Low speed/Full Speed
    USB Mouse can be connected to the PICtail USB adapter along with 
    Explorer 16 demo board. This file schedules the HID ransfers, and interprets
    the report received from the mouse. X & Y axis coordinates, Left & Right Click
    received from the mouse are diaplayed on the the LCD display mounted on the
    Explorer 16 board. Demo gives a fair idea of the HID host and user should be
    able to incorporate necessary changes for the required application.

* File Name:       Mouse_demo.c
* Dependencies:    None
* Processor:       PIC24FJ256GB110
* Compiler:        C30 v2.01
* Company:         Microchip Technology, Inc.

Software License Agreement

The software supplied herewith by Microchip Technology Incorporated
(the �Company�) for its PICmicro� Microcontroller is intended and
supplied to you, the Company�s customer, for use solely and
exclusively on Microchip PICmicro Microcontroller products. The
software is owned by the Company and/or its supplier, and is
protected under applicable copyright laws. All rights are reserved.
Any use in violation of the foregoing restrictions may subject the
user to criminal sanctions under applicable laws, as well as to
civil liability for the breach of the terms and conditions of this
license.

THIS SOFTWARE IS PROVIDED IN AN �AS IS� CONDITION. NO WARRANTIES,
WHETHER EXPRESS, IMPLIED OR STATUTORY, INCLUDING, BUT NOT LIMITED
TO, IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE APPLY TO THIS SOFTWARE. THE COMPANY SHALL NOT,
IN ANY CIRCUMSTANCES, BE LIABLE FOR SPECIAL, INCIDENTAL OR
CONSEQUENTIAL DAMAGES, FOR ANY REASON WHATSOEVER.

*******************************************************************************/

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "GenericTypeDefs.h"
#include "HardwareProfile.h"
#include "usb_config.h"
#include "USB\usb.h"
#include "USB\usb_host_hid_parser.h"
#include "USB\usb_host_hid.h"
#include <plib.h>
#include <P32xxxx.h>


// *****************************************************************************
// *****************************************************************************
// Data Structures
// *****************************************************************************
// *****************************************************************************

typedef enum _APP_STATE
{
    DEVICE_NOT_CONNECTED,
    DEVICE_CONNECTED, /* Device Enumerated  - Report Descriptor Parsed */
    READY_TO_TX_RX_REPORT,
    GET_INPUT_REPORT, /* perform operation on received report */
    INPUT_REPORT_PENDING,
    ERROR_REPORTED 
} APP_STATE;

typedef struct _HID_REPORT_BUFFER
{
    WORD  Report_ID;
    WORD  ReportSize;
//    BYTE* ReportData;
    BYTE  ReportData[4];
    WORD  ReportPollRate;
}   HID_REPORT_BUFFER;

// *****************************************************************************
// *****************************************************************************
// Internal Function Prototypes
// *****************************************************************************
// *****************************************************************************
BYTE App_DATA2ASCII(BYTE a);
void AppInitialize(void);
BOOL AppGetParsedReportDetails(void);
void App_Detect_Device(void);
BOOL USB_HID_DataCollectionHandler(void);

void App_ProcessInputReport(short *xLoc, short *yLoc);
void initspi(void);
long spi_send_receive(long send);

// *****************************************************************************
// *****************************************************************************
// Macros
// *****************************************************************************
// *****************************************************************************
#define MAX_ALLOWED_CURRENT             (500)         // Maximum power we can supply in mA
#define MINIMUM_POLL_INTERVAL           (0x0A)        // Minimum Polling rate for HID reports is 10ms

#define USAGE_PAGE_BUTTONS              (0x09)

#define USAGE_PAGE_GEN_DESKTOP          (0x01)


#define MAX_ERROR_COUNTER               (10)


// *****************************************************************************
// *****************************************************************************
// Global Variables
// *****************************************************************************
// *****************************************************************************

APP_STATE App_State_Mouse = DEVICE_NOT_CONNECTED;

HID_DATA_DETAILS Appl_Mouse_Buttons_Details;
HID_DATA_DETAILS Appl_XY_Axis_Details;

HID_REPORT_BUFFER  Appl_raw_report_buffer;

HID_USER_DATA_SIZE Appl_Button_report_buffer[3];
HID_USER_DATA_SIZE Appl_XY_report_buffer[3];

BYTE ErrorDriver;
BYTE ErrorCounter;
BYTE NumOfBytesRcvd;

BOOL ReportBufferUpdated;
BOOL LED_Key_Pressed = FALSE;

BYTE currCharPos;
BYTE FirstKeyPressed ;

short mouseMvt = 0;

//******************************************************************************
//******************************************************************************
// Main
//******************************************************************************
//******************************************************************************


int main (void)
{
    	BYTE i;
        int  value;

		short xPosition = 0; // To store x location
		short yPosition = 0; // To store y location
		
		long toSend =0;

		initspi();
        value = SYSTEMConfigWaitStatesAndPB( GetSystemClock() );
    
        // Enable the cache for the best performance
        CheKseg0CacheOn();
    
        INTEnableSystemMultiVectoredInt();
            
        TRISF = 0xFFFF;
  		TRISE = 0xFFFF;
  		TRISB = 0xFFFF;
  		TRISG = 0xFFFF;
		
    	TRISD = 0x0000;
        PORTD = 0x5;
        // Initialize USB layers
        USBInitialize( 0 );
        while(1)
        {
            USBTasks();
            App_Detect_Device();
            
            switch(App_State_Mouse)
            {
                case DEVICE_NOT_CONNECTED:
                             USBTasks();
                             
                             if(USBHostHID_ApiDeviceDetect()) /* True if report descriptor is parsed with no error */
                             {
                                App_State_Mouse = DEVICE_CONNECTED;
                             }
                    break;
                case DEVICE_CONNECTED:
                           App_State_Mouse = READY_TO_TX_RX_REPORT;
                    break;
                case READY_TO_TX_RX_REPORT:
                             if(!USBHostHID_ApiDeviceDetect())
                             {
                                App_State_Mouse = DEVICE_NOT_CONNECTED;
                             }
                             else
                             {
                                App_State_Mouse = GET_INPUT_REPORT;
                             }

                    break;
                case GET_INPUT_REPORT:
                            if(USBHostHID_ApiGetReport(Appl_raw_report_buffer.Report_ID,0,
                                                        Appl_raw_report_buffer.ReportSize, Appl_raw_report_buffer.ReportData))
                            {
                               /* Host may be busy/error -- keep trying */
                            }
                            else
                            {
                                App_State_Mouse = INPUT_REPORT_PENDING;
                            }
                            USBTasks();
                    break;
                case INPUT_REPORT_PENDING:
                           if(USBHostHID_ApiTransferIsComplete(&ErrorDriver,&NumOfBytesRcvd))
                            {
                                if(ErrorDriver ||(NumOfBytesRcvd != Appl_raw_report_buffer.ReportSize ))
                                {
                                  ErrorCounter++ ; 
                                  if(MAX_ERROR_COUNTER <= ErrorDriver)
                                     App_State_Mouse = ERROR_REPORTED;
                                  else
                                     App_State_Mouse = READY_TO_TX_RX_REPORT;
                                }
                                else
                                {
                                  ErrorCounter = 0; 
                                  ReportBufferUpdated = TRUE;
                                  App_State_Mouse = READY_TO_TX_RX_REPORT;

                                  App_ProcessInputReport( &xPosition, &yPosition);
  								  //Now we want to send the values to the FPGA by magic/SPI
								  toSend = ((((long) xPosition) << 16) | ((long) yPosition));
								  spi_send_receive(toSend);
                                }
                            }
                    break;

               case ERROR_REPORTED:
                    break;
                default:
                    break;

            }


        }
}


void App_ProcessInputReport(short *xLoc, short *yLoc)
{
    BYTE  data;
	short xMvmt, yMvmt;
   /* process input report received from device */
    USBHostHID_ApiImportData(Appl_raw_report_buffer.ReportData, Appl_raw_report_buffer.ReportSize
                          ,Appl_Button_report_buffer, &Appl_Mouse_Buttons_Details);
    USBHostHID_ApiImportData(Appl_raw_report_buffer.ReportData, Appl_raw_report_buffer.ReportSize
                          ,Appl_XY_report_buffer, &Appl_XY_Axis_Details);

    
    xMvmt = (signed char) Appl_XY_report_buffer[0];	// Get X-axis movement from report
	//PORTD = *xLoc;	// Write to LEDs to show mouse is working
    yMvmt = (signed char) Appl_XY_report_buffer[1];	// Get Y-axis movement from report
    
	*xLoc = *xLoc + xMvmt; //Adjust the current column value
	*yLoc = *yLoc + yMvmt; //Adjust the curent row value
	
	if(*xLoc < 0)
	{
		*xLoc = 0;
	}
	else if(*xLoc > 640)
	{
		*xLoc = 640;
	}
	if(*yLoc < 0)
	{
		*yLoc = 0;
	}
	else if(*yLoc > 480)
	{
		*yLoc = 480;
	}
}

//******************************************************************************
//******************************************************************************
// SPI Support Functions
//******************************************************************************
//******************************************************************************

void initspi(void) {
	char junk;

	SPI2CONbits.ON = 0; // disable SPI to reset any previous state
	junk = SPI2BUF; // read SPI buffer to clear the receive buffer
	SPI2BRG = 7; //set BAUD rate to 1.25MHz, with Pclk at 20MHz 
	SPI2CONbits.MSTEN = 1; // enable master mode
	SPI2CONbits.CKE = 1; // set clock-to-data timing (data centered on rising SCK edge) 
	SPI2CONbits.MODE32 = 1; // Send 16 bits at a time (a short)
	SPI2CONbits.MODE16 = 1; // Send 16 bits at a time (a short)
	SPI2CONbits.ON = 1; // turn SPI on
}

long spi_send_receive(long send) {
	SPI2BUF = send; // send data to slave
	while (!SPI2STATbits.SPIBUSY); // wait until received buffer fills, indicating data received 
	return SPI2BUF; // return received data and clear the read buffer full
}

//******************************************************************************
//******************************************************************************
// USB Support Functions
//******************************************************************************
//******************************************************************************

BOOL USB_ApplicationEventHandler( BYTE address, USB_EVENT event, void *data, DWORD size )
{
    switch( event )
    {
        case EVENT_VBUS_REQUEST_POWER:
            // The data pointer points to a byte that represents the amount of power
            // requested in mA, divided by two.  If the device wants too much power,
            // we reject it.
            if (((USB_VBUS_POWER_EVENT_DATA*)data)->current <= (MAX_ALLOWED_CURRENT / 2))
            {
                return TRUE;
            }
            else
            {
              //  UART2PrintString( "\r\n***** USB Error - device requires too much current *****\r\n" );
            }
            break;

        case EVENT_VBUS_RELEASE_POWER:
            // Turn off Vbus power.
            // The PIC24F with the Explorer 16 cannot turn off Vbus through software.
            return TRUE;
            break;

        case EVENT_HUB_ATTACH:
        //    UART2PrintString( "\r\n***** USB Error - hubs are not supported *****\r\n" );
            return TRUE;
            break;

        case EVENT_UNSUPPORTED_DEVICE:
        //    UART2PrintString( "\r\n***** USB Error - device is not supported *****\r\n" );
            return TRUE;
            break;

        case EVENT_CANNOT_ENUMERATE:
        //   UART2PrintString( "\r\n***** USB Error - cannot enumerate device *****\r\n" );
            return TRUE;
            break;

        case EVENT_CLIENT_INIT_ERROR:
        //    UART2PrintString( "\r\n***** USB Error - client driver initialization error *****\r\n" );
            return TRUE;
            break;

        case EVENT_OUT_OF_MEMORY:
        //    UART2PrintString( "\r\n***** USB Error - out of heap memory *****\r\n" );
            return TRUE;
            break;

        case EVENT_UNSPECIFIED_ERROR:   // This should never be generated.
        //    UART2PrintString( "\r\n***** USB Error - unspecified *****\r\n" );
            return TRUE;
            break;

		case EVENT_HID_RPT_DESC_PARSED:
			 #ifdef APPL_COLLECT_PARSED_DATA
			     return(APPL_COLLECT_PARSED_DATA());
		     #else
				 return TRUE;
			 #endif
			break;

        default:
            break;
    }
    return FALSE;
}


/****************************************************************************
  Function:
    BYTE App_HID2ASCII(BYTE a)
  Description:
    This function converts the HID code of the key pressed to coressponding
    ASCII value. For Key strokes like Esc, Enter, Tab etc it returns 0.
***************************************************************************/
BYTE App_DATA2ASCII(BYTE a) //convert USB HID code (buffer[2 to 7]) to ASCII code
{
   if(a<=0x9)
    {
       return(a+0x30);
    }

   if(a>=0xA && a<=0xF) 
    {
       return(a+0x37);
    }

   return(0);
}


/****************************************************************************
  Function:
    void App_Detect_Device(void)
  Description:
    This function monitors the status of device connected/disconnected
    None
***************************************************************************/
void App_Detect_Device(void)
{
  if(!USBHostHID_ApiDeviceDetect())
  {
     App_State_Mouse = DEVICE_NOT_CONNECTED;
  }
}


/****************************************************************************
  Function:
    BOOL USB_HID_DataCollectionHandler(void)
  Description:
    This function is invoked by HID client , purpose is to collect the 
    details extracted from the report descriptor. HID client will store
    information extracted from the report descriptor in data structures.
    Application needs to create object for each report type it needs to 
    extract.
    For ex: HID_DATA_DETAILS Appl_ModifierKeysDetails;
    HID_DATA_DETAILS is defined in file usb_host_hid_appl_interface.h
    Each member of the structure must be initialized inside this function.
    Application interface layer provides functions :
    USBHostHID_ApiFindBit()
    USBHostHID_ApiFindValue()
    These functions can be used to fill in the details as shown in the demo
    code.

  Return Values:
    TRUE    - If the report details are collected successfully.
    FALSE   - If the application does not find the the supported format.

  Remarks:
    This Function name should be entered in the USB configuration tool
    in the field "Parsed Data Collection handler".
    If the application does not define this function , then HID cient 
    assumes that Application is aware of report format of the attached
    device.
***************************************************************************/
BOOL USB_HID_DataCollectionHandler(void)
{
  BYTE NumOfReportItem = 0;
  BYTE i;
  USB_HID_ITEM_LIST* pitemListPtrs;
  USB_HID_DEVICE_RPT_INFO* pDeviceRptinfo;
  HID_REPORTITEM *reportItem;
  HID_USAGEITEM *hidUsageItem;
  BYTE usageIndex;
  BYTE reportIndex;

  pDeviceRptinfo = USBHostHID_GetCurrentReportInfo(); // Get current Report Info pointer
  pitemListPtrs = USBHostHID_GetItemListPointers();   // Get pointer to list of item pointers

  BOOL status = FALSE;
   /* Find Report Item Index for Modifier Keys */
   /* Once report Item is located , extract information from data structures provided by the parser */
   NumOfReportItem = pDeviceRptinfo->reportItems;
   for(i=0;i<NumOfReportItem;i++)
    {
       reportItem = &pitemListPtrs->reportItemList[i];
       if((reportItem->reportType==hidReportInput) && (reportItem->dataModes == (HIDData_Variable|HIDData_Relative))&&
           (reportItem->globals.usagePage==USAGE_PAGE_GEN_DESKTOP))
        {
           /* We now know report item points to modifier keys */
           /* Now make sure usage Min & Max are as per application */
            usageIndex = reportItem->firstUsageItem;
            hidUsageItem = &pitemListPtrs->usageItemList[usageIndex];

            reportIndex = reportItem->globals.reportIndex;
            Appl_XY_Axis_Details.reportLength = (pitemListPtrs->reportList[reportIndex].inputBits + 7)/8;
            Appl_XY_Axis_Details.reportID = (BYTE)reportItem->globals.reportID;
            Appl_XY_Axis_Details.bitOffset = (BYTE)reportItem->startBit;
            Appl_XY_Axis_Details.bitLength = (BYTE)reportItem->globals.reportsize;
            Appl_XY_Axis_Details.count=(BYTE)reportItem->globals.reportCount;
            Appl_XY_Axis_Details.interfaceNum= USBHostHID_ApiGetCurrentInterfaceNum();
        }
        else if((reportItem->reportType==hidReportInput) && (reportItem->dataModes == HIDData_Variable)&&
           (reportItem->globals.usagePage==USAGE_PAGE_BUTTONS))
        {
           /* We now know report item points to modifier keys */
           /* Now make sure usage Min & Max are as per application */
            usageIndex = reportItem->firstUsageItem;
            hidUsageItem = &pitemListPtrs->usageItemList[usageIndex];

            reportIndex = reportItem->globals.reportIndex;
            Appl_Mouse_Buttons_Details.reportLength = (pitemListPtrs->reportList[reportIndex].inputBits + 7)/8;
            Appl_Mouse_Buttons_Details.reportID = (BYTE)reportItem->globals.reportID;
            Appl_Mouse_Buttons_Details.bitOffset = (BYTE)reportItem->startBit;
            Appl_Mouse_Buttons_Details.bitLength = (BYTE)reportItem->globals.reportsize;
            Appl_Mouse_Buttons_Details.count=(BYTE)reportItem->globals.reportCount;
            Appl_Mouse_Buttons_Details.interfaceNum= USBHostHID_ApiGetCurrentInterfaceNum();
        }
    }

   if(pDeviceRptinfo->reports == 1)
    {
        Appl_raw_report_buffer.Report_ID = 0;
        Appl_raw_report_buffer.ReportSize = (pitemListPtrs->reportList[reportIndex].inputBits + 7)/8;
//        Appl_raw_report_buffer.ReportData = (BYTE*)malloc(Appl_raw_report_buffer.ReportSize);
        Appl_raw_report_buffer.ReportPollRate = pDeviceRptinfo->reportPollingRate;
        status = TRUE;
    }

    return(status);
}

