classdef kinesis_piezo < instrumentType 
   %You can find what namespaces are used for a given model by opening 
   %program files/thorlabs/kinesis/thorlabs.MotionControl.DotNet_API
   %The models are listed on the contents section and you can pretty easily
   %find your model of controller (note: find the controller model, not the
   %motor itself). You can also find a list of all the functions by looking
   %in the Classes section
% https://www.thorlabs.com/software_pages/ViewSoftwarePage.cfm?Code=Motion_Control


    properties (SetAccess = protected, GetAccess = public)
       defaults
       namespaces
       dllPath
       serialNumber
       settingsTimeout
       handshake
       pollTime
       piezoConfiguration
    end

    properties (Dependent)
       voltage       
    end    

    methods

       function obj = disconnect(obj)
          obj.handshake.StopPolling()
          obj.handshake.Disconnect(true)
       end

       function obj = connect(obj,configName)
          if obj.connected
             return
          end

          %Loads config file and checks relevant field names
         configFields = {'defaults','settingsTimeout','fullClassName','pollTime'};
         commandFields = {};
         numericalFields = {};
         obj = loadConfig(obj,configName,configFields,commandFields,numericalFields);

         %Loads dlls downloaded from thorlabs website
          loadDLLs(obj)

          %Creates the MatLab firmware handshake to the instrument. The
          %classes are specific to the model of controller used (see intro)
          handshakeStart = strcat(obj.fullClassName,'(',obj.serialNumber,')');
          obj.handshake = feval(handshakeStart);
          obj.handshake.Connect(obj.serialNumber); %Connection between handshake to instrument itself

          %Wait for settings to initialize
          if ~obj.handshake.IsSettingsInitialized 
             obj.handshake.WaitForSettingsInitialized(obj.settingsTimeout);
          end

          %Make instrument start listening for external commands
          obj.handshake.StartPolling(obj.pollTime)

          wait(obj.pollTime*2)%Wait for device to process polling

          %Set device to ready state
          obj.handshake.EnableDevice()

          %Initialize and load device's piezo settings
          obj.piezoConfiguration = obj.handshake.GetPiezoConfiguration(obj.serialNumber);
       end

       function loadDLLs(obj)
          for ii = 1:numel(obj.namespaces)
            NET.addAssembly(strcat(obj.dllPath,obj.namespaces{ii},'.dll'))
          end
       end

       function obj = setAbsoluteVoltage(obj,voltageSet)
          %Finds the relative
          relativeChange = voltageSet - obj.voltage;
          obj = setRelativeVoltage(obj,relativeChange);
       end

       function obj = setRelativeVoltage(obj,voltageSet)
          if abs(voltageSet) < 1
             obj.handshake.Jog(voltageSet)
          else
             obj.handshake.SetOutputVoltage(voltageSet)
          end
       end

       function set.voltage(obj,val)
          obj = setAbsoluteVoltage(obj,val); %#ok<NASGU>
       end

       function val = get.voltage(obj)
          val = obj.handshake.GetOutputVoltage();
       end

    end

    methods (Static)
       function serialNumbers = getSerialNumbers
          Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.BuildDeviceList();  % Build device list
          serialNumbersNet = Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.GetDeviceList(); % Get device list
          serialNumbers=cell(ToArray(serialNumbersNet)); % Convert serial numbers to cell array
       end
    end
end