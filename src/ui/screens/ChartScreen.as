package ui.screens
{
	import com.freshplanet.ane.AirBackgroundFetch.BackgroundFetch;
	
	import flash.system.System;
	import flash.utils.clearTimeout;
	import flash.utils.setTimeout;
	
	import database.BgReading;
	import database.BlueToothDevice;
	import database.Calibration;
	import database.CommonSettings;
	
	import events.CalibrationServiceEvent;
	import events.FollowerEvent;
	import events.SpikeEvent;
	import events.TransmitterServiceEvent;
	import events.TreatmentsEvent;
	
	import feathers.controls.Check;
	import feathers.controls.Radio;
	import feathers.controls.ScrollBarDisplayMode;
	import feathers.controls.ScrollPolicy;
	import feathers.core.ToggleGroup;
	import feathers.events.FeathersEventType;
	import feathers.themes.BaseMaterialDeepGreyAmberMobileTheme;
	
	import model.ModelLocator;
	
	import services.CalibrationService;
	import services.NightscoutService;
	import services.TransmitterService;
	
	import starling.core.Starling;
	import starling.display.Shape;
	import starling.events.Event;
	import starling.events.ResizeEvent;
	import starling.utils.SystemUtil;
	
	import treatments.Treatment;
	import treatments.TreatmentsManager;
	
	import ui.AppInterface;
	import ui.chart.DistributionChart;
	import ui.chart.GlucoseChart;
	import ui.chart.GraphLayoutFactory;
	import ui.chart.PieDistributionSection;
	import ui.screens.display.LayoutFactory;
	
	import utils.Constants;
	import utils.DeviceInfo;
	import utils.Trace;
	
	[ResourceBundle("chartscreen")]
	
	public class ChartScreen extends BaseScreen
	{
		//Objects
		private var chartData:Array;
		private var newReadingsList:Array = [];
		private var newReadingsListFollower:Array = [];
		private var timeRangeGroup:ToggleGroup;
		
		//Visual variables
		private var glucoseChartTopPadding:int = 7;
		private var selectedTimelineRange:Number;
		private var drawLineChart:Boolean;
		private var mainChartHeight:Number;
		private var availableScreenHeight:Number;
		private var chartSettingsLeftRightPadding:int = 10;
		private var chartSettingsTopPadding:int = 10;
		private var delimitterTopPadding:int = 10;
		private var pieTopPadding:int = 15;
		private var pieChartHeight:Number;
		private var displayPieChart:Boolean;
		private var isPortrait:Boolean;
		
		//Logical Variables
		private var chartRequiresReload:Boolean = true;
		private var appInBackground:Boolean = false;
		private var queueTimeout:int = -1;
		private var treatmentsEnabled:Boolean = false;
		private var chartTreatmentsEnabled:Boolean = false;
		private var displayIOBEnabled:Boolean = false;
		private var displayCOBEnabled:Boolean = false;
		
		//Display Objects
		private var glucoseChart:GlucoseChart;
		private var pieChart:DistributionChart;
		private var h24:Radio;
		private var h12:Radio;
		private var h6:Radio;
		private var h3:Radio;
		private var h1:Radio;
		private var displayLines:Check;
		private var delimitter:Shape;
		
		public function ChartScreen() 
		{
			super();
			styleNameList.add( BaseMaterialDeepGreyAmberMobileTheme.THEME_STYLE_NAME_HEADER_WITH_SHADOW );
			styleNameList.add( BaseMaterialDeepGreyAmberMobileTheme.THEME_STYLE_NAME_PANEL_WITHOUT_PADDING );
		}
		
		override protected function initialize():void 
		{
			super.initialize();
			
			//Set Properties From Database
			selectedTimelineRange = Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CHART_SELECTED_TIMELINE_RANGE));
			drawLineChart = CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CHART_DISPLAY_LINE) == "true";
			displayPieChart = CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CHART_DISPLAY_GLUCOSE_DISTRIBUTION) == "true";
			treatmentsEnabled = CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_TREATMENTS_ENABLED) == "true";
			chartTreatmentsEnabled = CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_TREATMENTS_ON_CHART_ENABLED) == "true";
			displayIOBEnabled = CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_TREATMENTS_IOB_ENABLED) == "true";
			displayCOBEnabled = CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_TREATMENTS_COB_ENABLED) == "true";
			
			//Event listeners
			addEventListener(FeathersEventType.CREATION_COMPLETE, onCreation);
			Spike.instance.addEventListener(SpikeEvent.APP_IN_BACKGROUND, onAppInBackground);
			Spike.instance.addEventListener(SpikeEvent.APP_IN_FOREGROUND, onAppInForeground);
			TransmitterService.instance.addEventListener(TransmitterServiceEvent.BGREADING_EVENT, onBgReadingReceived);
			NightscoutService.instance.addEventListener(FollowerEvent.BG_READING_RECEIVED, onBgReadingReceivedFollower);
			CalibrationService.instance.addEventListener(CalibrationServiceEvent.INITIAL_CALIBRATION_EVENT, onInitialCalibrationReceived);
			TreatmentsManager.instance.addEventListener(TreatmentsEvent.TREATMENT_ADDED, onTreatmentAdded);
			TreatmentsManager.instance.addEventListener(TreatmentsEvent.TREATMENT_EXTERNALLY_MODIFIED, onTreatmentExternallyModified);
			TreatmentsManager.instance.addEventListener(TreatmentsEvent.TREATMENT_EXTERNALLY_DELETED, onTreatmentExternallyDeleted);
			TreatmentsManager.instance.addEventListener(TreatmentsEvent.IOB_COB_UPDATED, onUpdateIOBCOB);
			Starling.current.stage.addEventListener(starling.events.Event.RESIZE, onStarlingResize);
			
			//Scroll Policies
			scrollBarDisplayMode = ScrollBarDisplayMode.NONE;
			horizontalScrollPolicy = ScrollPolicy.OFF;
			verticalScrollPolicy = ScrollPolicy.OFF;
			
			//Reset Transitions
			AppInterface.instance.chartSettingsScreenItem.pushTransition = null;
			AppInterface.instance.chartSettingsScreenItem.popTransition = null;
			
			//Reset Menu
			AppInterface.instance.menu.selectedIndex = 0;
		}
		
		/**
		 * Display Objects Creation and Positioning
		 */
		private function createChart():void
		{
			var availableScreenHeight:Number = Constants.stageHeight - this.header.height;
			mainChartHeight = availableScreenHeight;
			
			if (Constants.isPortrait)
			{
				//Calculate timeline ranges and display line height
				mainChartHeight -= chartSettingsTopPadding; //Top padding for settings
				mainChartHeight -= calculateChartSettingsSize(); //Height of settings components
				mainChartHeight -= delimitterTopPadding; //Bottom padding for settings
				
				if (displayPieChart)
					mainChartHeight -= calculatePieChartSize();
			}
			
			//Get glucose data;
			chartData = ModelLocator.bgReadings.concat();
			
			//Create and setup glucose chart
			glucoseChart = new GlucoseChart(selectedTimelineRange, Constants.stageWidth, mainChartHeight);
			glucoseChart.y = Math.round(glucoseChartTopPadding);
			glucoseChart.dataSource = chartData;
			glucoseChart.displayLine = drawLineChart;
			glucoseChart.drawGraph();
			glucoseChart.addAllTreatments();
			var now:Number = new Date().valueOf();
			SystemUtil.executeWhenApplicationIsActive( glucoseChart.calculateTotalIOB, now );
			SystemUtil.executeWhenApplicationIsActive( glucoseChart.calculateTotalCOB, now );
			addChild(glucoseChart);
			
			if (Constants.isPortrait)
			{
				createSettings();
				
				if (displayPieChart)
					createPieChart();
			}
		}
		
		private function createSettings():void
		{
			//Position Radio/Check Buttons
			var paddingMultiplier:Number = DeviceInfo.getHorizontalPaddingMultipier();
			
			h24.x = stage.stageWidth - h24.width - chartSettingsLeftRightPadding;
			h24.y = glucoseChart.y + glucoseChart.height + chartSettingsTopPadding;
			addChild(h24);
			
			h12.x = h24.x - h12.width - (chartSettingsLeftRightPadding * paddingMultiplier);
			h12.y = h24.y;
			addChild(h12);
			
			h6.x = h12.x - h6.width - (chartSettingsLeftRightPadding * paddingMultiplier);
			h6.y = h24.y;
			addChild(h6);
			
			h3.x = h6.x - h3.width - (chartSettingsLeftRightPadding * paddingMultiplier);
			h3.y = h24.y;
			addChild(h3);
			
			h1.x = h3.x - h1.width - (chartSettingsLeftRightPadding * paddingMultiplier);
			h1.y = h24.y;
			addChild(h1);
			
			displayLines.x = chartSettingsLeftRightPadding;
			displayLines.y = h24.y;
			addChild(displayLines);
			
			//Radio Buttons Group
			if (selectedTimelineRange == GlucoseChart.TIMELINE_1H)
				timeRangeGroup.selectedItem = h1;
			else if (selectedTimelineRange == GlucoseChart.TIMELINE_3H)
				timeRangeGroup.selectedItem = h3;
			else if (selectedTimelineRange == GlucoseChart.TIMELINE_6H)
				timeRangeGroup.selectedItem = h6;
			else if (selectedTimelineRange == GlucoseChart.TIMELINE_12H)
				timeRangeGroup.selectedItem = h12;
			else if (selectedTimelineRange == GlucoseChart.TIMELINE_24H)
				timeRangeGroup.selectedItem = h24;
			
			//Add Event Listener For Radios
			timeRangeGroup.addEventListener( Event.CHANGE, onTimeRangeChange );
		}
		
		private function createPieChart():void
		{
			delimitter = GraphLayoutFactory.createHorizontalLine(Constants.stageWidth, 1, 0x282a32);
			delimitter.y = h24.y + h24.height + delimitterTopPadding;
			addChild(delimitter);
			
			pieChart = new DistributionChart((pieChartHeight / 2), chartData);
			pieChart.y = Math.round(delimitter.y + delimitter.height + pieTopPadding);
			pieChart.x = 10;
			addChild(pieChart);
		}
		
		private function redrawChartForTreatmentsAndLine():void
		{
			setTimeout(redrawChart, 1500);
		}
		
		private function redrawChart():void
		{
			if (BackgroundFetch.appIsInForeground() && Constants.appInForeground)
			{
				chartData = glucoseChart.dataSource;
				
				//Remove previous chart
				removeChild(glucoseChart);
				glucoseChart.dispose();
				glucoseChart = null;
				
				//Create new chart
				glucoseChart = new GlucoseChart(selectedTimelineRange, Constants.stageWidth, mainChartHeight);
				glucoseChart.dataSource = chartData;
				glucoseChart.displayLine = drawLineChart;
				glucoseChart.drawGraph();
				glucoseChart.addAllTreatments();
				var now:Number = new Date().valueOf();
				SystemUtil.executeWhenApplicationIsActive( glucoseChart.calculateTotalIOB, now );
				SystemUtil.executeWhenApplicationIsActive( glucoseChart.calculateTotalCOB, now );
				glucoseChart.y = glucoseChartTopPadding;
				addChild(glucoseChart);
			}
			else
				SystemUtil.executeWhenApplicationIsActive( redrawChartForTreatmentsAndLine );
		}
		
		/**
		 * Display Objects Size Calculators
		 */
		private function calculateChartSettingsSize():Number
		{
			var chartSettingsHeight:Number = 0;
			
			/* Line Settings */
			displayLines = LayoutFactory.createCheckMark(false, ModelLocator.resourceManagerInstance.getString('chartscreen','check_box_line_title'));
			if (Constants.deviceModel == DeviceInfo.IPHONE_X || Constants.deviceModel == DeviceInfo.IPHONE_2G_3G_3GS_4_4S_ITOUCH_2_3_4)
				displayLines.scale = 0.8;
			else if (Constants.deviceModel == DeviceInfo.IPAD_1_2_3_4_5_AIR1_2_PRO_97 || Constants.deviceModel == DeviceInfo.IPAD_PRO_105 || Constants.deviceModel == DeviceInfo.IPAD_PRO_129)
				displayLines.scale = 1.4;
			displayLines.isSelected = drawLineChart;
			displayLines.addEventListener( Event.CHANGE, onDisplayLine );
			displayLines.validate();
			
			chartSettingsHeight = displayLines.height;
			
			/* Timeline Settings */
			timeRangeGroup = new ToggleGroup();
			
			//Create Radios
			h1 = LayoutFactory.createRadioButton(ModelLocator.resourceManagerInstance.getString('chartscreen','radio_button_1h_title'), timeRangeGroup);
			if (Constants.deviceModel == DeviceInfo.IPHONE_X || Constants.deviceModel == DeviceInfo.IPHONE_2G_3G_3GS_4_4S_ITOUCH_2_3_4)
				h1.scale = 0.8;
			else if (Constants.deviceModel == DeviceInfo.IPAD_1_2_3_4_5_AIR1_2_PRO_97 || Constants.deviceModel == DeviceInfo.IPAD_PRO_105 || Constants.deviceModel == DeviceInfo.IPAD_PRO_129)
				h1.scale = 1.4;
			h1.validate();
			
			h3 = LayoutFactory.createRadioButton(ModelLocator.resourceManagerInstance.getString('chartscreen','radio_button_3h_title'), timeRangeGroup);
			if (Constants.deviceModel == DeviceInfo.IPHONE_X || Constants.deviceModel == DeviceInfo.IPHONE_2G_3G_3GS_4_4S_ITOUCH_2_3_4)
				h3.scale = 0.8;
			else if (Constants.deviceModel == DeviceInfo.IPAD_1_2_3_4_5_AIR1_2_PRO_97 || Constants.deviceModel == DeviceInfo.IPAD_PRO_105 || Constants.deviceModel == DeviceInfo.IPAD_PRO_129)
				h3.scale = 1.4;
			h3.validate();
			
			h6 = LayoutFactory.createRadioButton(ModelLocator.resourceManagerInstance.getString('chartscreen','radio_button_6h_title'), timeRangeGroup);
			if (Constants.deviceModel == DeviceInfo.IPHONE_X || Constants.deviceModel == DeviceInfo.IPHONE_2G_3G_3GS_4_4S_ITOUCH_2_3_4)
				h6.scale = 0.8;
			else if (Constants.deviceModel == DeviceInfo.IPAD_1_2_3_4_5_AIR1_2_PRO_97 || Constants.deviceModel == DeviceInfo.IPAD_PRO_105 || Constants.deviceModel == DeviceInfo.IPAD_PRO_129)
				h6.scale = 1.4;
			h6.validate();
			
			h12 = LayoutFactory.createRadioButton(ModelLocator.resourceManagerInstance.getString('chartscreen','radio_button_12h_title'), timeRangeGroup);
			if (Constants.deviceModel == DeviceInfo.IPHONE_X || Constants.deviceModel == DeviceInfo.IPHONE_2G_3G_3GS_4_4S_ITOUCH_2_3_4)
				h12.scale = 0.8;
			else if (Constants.deviceModel == DeviceInfo.IPAD_1_2_3_4_5_AIR1_2_PRO_97 || Constants.deviceModel == DeviceInfo.IPAD_PRO_105 || Constants.deviceModel == DeviceInfo.IPAD_PRO_129)
				h12.scale = 1.4;
			h12.validate();
			
			h24 = LayoutFactory.createRadioButton(ModelLocator.resourceManagerInstance.getString('chartscreen','radio_button_24h_title'), timeRangeGroup);
			if (Constants.deviceModel == DeviceInfo.IPHONE_X || Constants.deviceModel == DeviceInfo.IPHONE_2G_3G_3GS_4_4S_ITOUCH_2_3_4)
				h24.scale = 0.8;
			else if (Constants.deviceModel == DeviceInfo.IPAD_1_2_3_4_5_AIR1_2_PRO_97 || Constants.deviceModel == DeviceInfo.IPAD_PRO_105 || Constants.deviceModel == DeviceInfo.IPAD_PRO_129)
				h24.scale = 1.4;
			h24.validate();
			
			return chartSettingsHeight;
		}
		
		private function calculatePieChartSize():Number
		{
			var pieChartTotalHeight:Number = 0;
			
			if (Constants.deviceModel == DeviceInfo.IPHONE_2G_3G_3GS_4_4S_ITOUCH_2_3_4)
				pieTopPadding = 10;
			
			pieChartTotalHeight += pieTopPadding * 2;
			
			/*pieChartHeight = 65;
			if (Constants.deviceModel == DeviceInfo.IPHONE_6_6S_7_8)
			pieChartHeight = 100;*/
			
			var dummyPieChartStatsSection:PieDistributionSection = new PieDistributionSection(100, 30, 0x000000, 0x000000, 0x000000);
			dummyPieChartStatsSection.title.text = "N/A";
			dummyPieChartStatsSection.title.validate();
			dummyPieChartStatsSection.message.text = "N/A";
			dummyPieChartStatsSection.message.validate();
			
			var sectionMultiplier:Number = 3;
			if (Constants.deviceModel == DeviceInfo.IPHONE_2G_3G_3GS_4_4S_ITOUCH_2_3_4)
				sectionMultiplier = 2.5;
			
			pieChartHeight = (sectionMultiplier * dummyPieChartStatsSection.title.height) + (sectionMultiplier * dummyPieChartStatsSection.message.height);
			
			dummyPieChartStatsSection.dispose();
			dummyPieChartStatsSection = null;
			
			pieChartTotalHeight += pieChartHeight;
			
			return pieChartTotalHeight;
		}
		
		/**
		 * Event Handlers
		 */
		private function onCreation(event:Event):void
		{
			createChart();
			redrawChartForTreatmentsAndLine();
		}
		
		private function onBgReadingReceivedFollower(e:FollowerEvent):void
		{
			Trace.myTrace("ChartScreen.as", "on onBgReadingReceivedFollower!");
			
			if (!BlueToothDevice.isFollower())
				Trace.myTrace("ChartScreen.as", "User is not a follower. Ignoring");
			
			try
			{
				var readings:Array = e.data;
				if (readings != null && readings.length > 0)
				{
					if (BackgroundFetch.appIsInForeground() && glucoseChart != null && Constants.appInForeground && SystemUtil.isApplicationActive)
					{
						glucoseChart.addGlucose(readings);
						if (displayPieChart)
							pieChart.drawChart();
					}
					else
					{
						newReadingsListFollower = newReadingsListFollower.concat(readings);
					}		
				}	
			} 
			catch(error:Error) 
			{
				Trace.myTrace("ChartScreen.as", "Error adding glucose to chart. Error: " + error.message);
			}
		}
		
		private function onBgReadingReceived(event:TransmitterServiceEvent):void
		{
			Trace.myTrace("ChartScreen.as", "on onBgReadingReceived!");
			
			if (BlueToothDevice.isFollower())
			{
				Trace.myTrace("ChartScreen.as", "User is a follower. Ignoring");
				return;
			}
			
			try
			{
				var reading:BgReading = BgReading.lastNoSensor();
				
				if(reading == null || reading.calculatedValue == 0 || Calibration.allForSensor().length < 2)
				{
					Trace.myTrace("ChartScreen.as", "Bad Reading or not enough calibrations. Not adding it to the chart.");
					return;
				}
				
				if (!appInBackground && glucoseChart != null && Constants.appInForeground && BackgroundFetch.appIsInForeground() && SystemUtil.isApplicationActive)
				{
					Trace.myTrace("ChartScreen.as", "Adding reading to the chart: Value: " + reading.calculatedValue);
					glucoseChart.addGlucose([reading]);
					if (displayPieChart)
						pieChart.drawChart();
				}
				else
				{
					Trace.myTrace("ChartScreen.as", "Adding reading to the queue. Will be rendered when the app is in the foreground. Reading: " + reading.calculatedValue);
					newReadingsList.push(reading);
				}
			} 
			catch(error:Error) 
			{
				Trace.myTrace("ChartScreen.as", "Error adding readings to chart. Error: " + error.message)
			}
		}
		
		private function onInitialCalibrationReceived(e:CalibrationServiceEvent):void
		{
			onBgReadingReceived(null);
		}
		
		private function onUpdateIOBCOB(e:TreatmentsEvent):void
		{
			if (glucoseChart == null || !BackgroundFetch.appIsInForeground() || !Constants.appInForeground)
				return;
			
			Trace.myTrace("ChartScreen.as", "Updating IOB/COB");
			
			var now:Number = new Date().valueOf();
			SystemUtil.executeWhenApplicationIsActive(glucoseChart.calculateTotalIOB, now);
			SystemUtil.executeWhenApplicationIsActive(glucoseChart.calculateTotalCOB, now);
		}
		
		private function onTreatmentAdded(e:TreatmentsEvent):void
		{
			var treatment:Treatment = e.treatment;
			if (treatment != null && glucoseChart != null)
			{
				Trace.myTrace("ChartScreen.as", "Adding treatment to the chart: Type: " + treatment.type);
				SystemUtil.executeWhenApplicationIsActive(glucoseChart.addTreatment, treatment);
			}
		}
		
		private function onTreatmentExternallyModified(e:TreatmentsEvent):void
		{
			var treatment:Treatment = e.treatment;
			if (treatment != null && glucoseChart != null)
			{
				Trace.myTrace("ChartScreen.as", "Sending externally modified treatment to the chart: Type: " + treatment.type);
				SystemUtil.executeWhenApplicationIsActive(glucoseChart.updateExternallyModifiedTreatment, treatment);
			}
		}
		
		private function onTreatmentExternallyDeleted(e:TreatmentsEvent):void
		{
			var treatment:Treatment = e.treatment;
			if (treatment != null && glucoseChart != null)
			{
				Trace.myTrace("ChartScreen.as", "Sending externally deleted treatment to the chart: Type: " + treatment.type);
				SystemUtil.executeWhenApplicationIsActive(glucoseChart.updateExternallyDeletedTreatment, treatment);
			}
		}
		
		private function onAppInBackground (e:SpikeEvent):void
		{
			appInBackground = true;
		}
		
		private function onAppInForeground (e:SpikeEvent):void
		{
			SystemUtil.executeWhenApplicationIsActive( processQueue );
		}
		
		private function processQueue():void
		{
			clearTimeout(queueTimeout);
			
			if(!BackgroundFetch.appIsInForeground() || !Constants.appInForeground)
			{
				queueTimeout = setTimeout(processQueue, 150); //retry in 150ms
				
				return;
			}
			
			try
			{
				if (appInBackground)
				{
					var queueAddedToChart:Boolean = false;
					var queueAddedToPie:Boolean = false;
					
					appInBackground = false;
					
					if (!BlueToothDevice.isFollower())
					{
						if (newReadingsList != null && newReadingsList.length > 0 && glucoseChart != null)
						{
							if (glucoseChart.addGlucose(newReadingsList))
								queueAddedToChart = true;
							
							if (displayPieChart && pieChart != null)
							{
								if (pieChart.drawChart())
									queueAddedToPie = true;
							}
							else
								queueAddedToPie = true;
							
							if (queueAddedToChart && queueAddedToPie)
								newReadingsList.length = 0;
						}
						else
							if (glucoseChart != null)
								glucoseChart.calculateDisplayLabels();
					}
					else
					{
						if (newReadingsListFollower != null && newReadingsListFollower.length > 0 && glucoseChart != null)
						{
							if (glucoseChart.addGlucose(newReadingsListFollower))
								queueAddedToChart = true;
							
							if (displayPieChart && pieChart != null)
							{
								if (pieChart.drawChart())
									queueAddedToPie = true;
							}
							else
								queueAddedToPie = true;
							
							if (queueAddedToChart && queueAddedToPie)
								newReadingsListFollower.length = 0;
						}	
						else if (glucoseChart != null)
							glucoseChart.calculateDisplayLabels();
					}
				}
			} 
			catch(error:Error)
			{
				Trace.myTrace("ChartScreen.as", "Error adding queue to chart when app came to the foreground. Error: " + error.message);
				
				queueTimeout = setTimeout(processQueue, 150); //retry in 150ms
			}
		}
		
		private function onTimeRangeChange(event:Event):void
		{
			var group:ToggleGroup = ToggleGroup( event.currentTarget );
			if (group.selectedIndex == 0)
			{
				//1H
				selectedTimelineRange = GlucoseChart.TIMELINE_1H;
				redrawChart();
			}
			else if (group.selectedIndex == 1)
			{
				//3H
				selectedTimelineRange = GlucoseChart.TIMELINE_3H;
				redrawChart();
			}
			else if (group.selectedIndex == 2)
			{
				//6H
				selectedTimelineRange = GlucoseChart.TIMELINE_6H;
				redrawChart();
			}
			else if (group.selectedIndex == 3)
			{
				//12H
				selectedTimelineRange = GlucoseChart.TIMELINE_12H;
				redrawChart();
			}
			else if (group.selectedIndex == 4)
			{
				//24H
				selectedTimelineRange = GlucoseChart.TIMELINE_24H;
				redrawChart();
			}
			
			//Save timerange in database
			if (Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CHART_SELECTED_TIMELINE_RANGE)) != selectedTimelineRange)
				CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_CHART_SELECTED_TIMELINE_RANGE, String(selectedTimelineRange));
		}
		
		private function onDisplayLine(event:Event):void
		{
			var check:Check = Check( event.currentTarget );
			if(check.isSelected)
			{
				glucoseChart.showLine();
				drawLineChart = true;
			}
			else
			{
				glucoseChart.hideLine();
				drawLineChart = false;
			}
			
			//Save setting to database
			if (drawLineChart)
				CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_CHART_DISPLAY_LINE, "true");
			else
				CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_CHART_DISPLAY_LINE, "false");
		}
		
		private function onStarlingResize(event:ResizeEvent):void 
		{
			disposeDisplayObjects();
			onCreation(null);
		}
		
		/**
		 * Utility
		 */
		private function disposeDisplayObjects():void
		{
			if (glucoseChart != null)
			{
				glucoseChart.removeFromParent();
				glucoseChart.dispose();
				glucoseChart = null;
			}
			
			if (pieChart != null)
			{
				pieChart.removeFromParent();
				pieChart.dispose();
				pieChart = null;
			}
			
			if (timeRangeGroup != null)
			{
				timeRangeGroup.removeEventListener( Event.CHANGE, onTimeRangeChange );
				timeRangeGroup = null;
			}
			
			if (h24 != null)
			{
				h24.removeFromParent();
				h24.dispose();
				h24 = null;
			}
			
			if (h12 != null)
			{
				h12.removeFromParent();
				h12.dispose();
				h12 = null;
			}
			
			if (h6 != null)
			{
				h6.removeFromParent();
				h6.dispose();
				h6 = null;
			}
			
			if (h3 != null)
			{
				h3.removeFromParent();
				h3.dispose();
				h3 = null;
			}
			
			if (h1 != null)
			{
				h1.removeFromParent();
				h1.dispose();
				h1 = null;
			}
			
			if (displayLines != null)
			{
				displayLines.removeEventListener( Event.CHANGE, onDisplayLine );
				displayLines.removeFromParent();
				displayLines.dispose();
				displayLines = null;
			}
			
			if (delimitter != null)
			{
				delimitter.removeFromParent();
				delimitter.dispose();
				delimitter = null;
			}
		}
		
		override public function dispose():void
		{
			/* Event Listeners */
			Spike.instance.removeEventListener(SpikeEvent.APP_IN_BACKGROUND, onAppInBackground);
			Spike.instance.removeEventListener(SpikeEvent.APP_IN_FOREGROUND, onAppInForeground);
			TransmitterService.instance.removeEventListener(TransmitterServiceEvent.BGREADING_EVENT, onBgReadingReceived);
			CalibrationService.instance.removeEventListener(CalibrationServiceEvent.INITIAL_CALIBRATION_EVENT, onInitialCalibrationReceived);
			NightscoutService.instance.removeEventListener(FollowerEvent.BG_READING_RECEIVED, onBgReadingReceivedFollower);
			removeEventListener(FeathersEventType.CREATION_COMPLETE, onCreation);
			TreatmentsManager.instance.removeEventListener(TreatmentsEvent.TREATMENT_ADDED, onTreatmentAdded);
			TreatmentsManager.instance.removeEventListener(TreatmentsEvent.TREATMENT_EXTERNALLY_MODIFIED, onTreatmentExternallyModified);
			TreatmentsManager.instance.removeEventListener(TreatmentsEvent.TREATMENT_EXTERNALLY_DELETED, onTreatmentExternallyDeleted);
			TreatmentsManager.instance.removeEventListener(TreatmentsEvent.IOB_COB_UPDATED, onUpdateIOBCOB);
			Starling.current.stage.removeEventListener(starling.events.Event.RESIZE, onStarlingResize);
			
			/* Display Objects */
			disposeDisplayObjects();
			
			/* Objects */
			if (chartData != null)
			{
				chartData.length = 0;
				chartData = null;
			}
			
			if (newReadingsList != null)
			{
				newReadingsList.length = 0;
				newReadingsList = null;
			}
			
			super.dispose();
			
			System.pauseForGCIfCollectionImminent(0);
		}
	}
}