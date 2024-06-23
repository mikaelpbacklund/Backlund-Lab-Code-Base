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

       function h = disconnect(h)
          h.handshake.StopPolling()
          h.handshake.Disconnect(true)
       end

       function h = connect(h,configName)
          if h.connected
             return
          end

          %Loads config file and checks relevant field names
         configFields = {'defaults','settingsTimeout','fullClassName','pollTime'};
         commandFields = {};
         numericalFields = {};
         h = loadConfig(h,configName,configFields,commandFields,numericalFields);

         %Loads dlls downloaded from thorlabs website
          loadDLLs(h)

          %Creates the MatLab firmware handshake to the instrument. The
          %classes are specific to the model of controller used (see intro)
          handshakeStart = strcat(h.fullClassName,'(',h.serialNumber,')');
          h.handshake = feval(handshakeStart);
          h.handshake.Connect(h.serialNumber); %Connection between handshake to instrument itself

          %Wait for settings to initialize
          if ~h.handshake.IsSettingsInitialized 
             h.handshake.WaitForSettingsInitialized(h.settingsTimeout);
          end

          %Make instrument start listening for external commands
          h.handshake.StartPolling(h.pollTime)

          wait(h.pollTime*2)%Wait for device to process polling

          %Set device to ready state
          h.handshake.EnableDevice()

          %Initialize and load device's piezo settings
          h.piezoConfiguration = h.handshake.GetPiezoConfiguration(h.serialNumber);
       end

       function loadDLLs(h)
          for ii = 1:numel(h.namespaces)
            NET.addAssembly(strcat(h.dllPath,h.namespaces{ii},'.dll'))
          end
       end

       function h = setAbsoluteVoltage(h,voltageSet)
          %Finds the relative
          relativeChange = voltageSet - h.voltage;
          h = setRelativeVoltage(h,relativeChange);
       end

       function h = setRelativeVoltage(h,voltageSet)
          if abs(voltageSet) < 1
             h.handshake.Jog(voltageSet)
          else
             h.handshake.SetOutputVoltage(voltageSet)
          end
       end

       function set.voltage(h,val)
          h = setAbsoluteVoltage(h,val); %#ok<NASGU>
       end

       function val = get.voltage(h)
          val = h.handshake.GetOutputVoltage();
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