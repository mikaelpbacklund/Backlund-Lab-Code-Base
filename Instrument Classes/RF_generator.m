classdef RF_generator < instrumentType
   %Internal functions may need changes depending on exact instrumentation
   %and connection
   properties
      enabled
      frequency
      amplitude
      modulationEnabled
      modulationType
      modulationWaveform
   end

   properties (SetAccess = {?RF_generator_beta ?instrumentType}, GetAccess = public)
      %Read-only
      frequencyInfo
      amplitudeInfo
      commands
      handshake
      connectionInfo
   end

      methods %Misc

      function obj = RF_generator(configFileName)

          if nargin < 1
              error('Config file name required as input')
          end

         %Loads config file and checks relevant field names
         configFields = {'connectionInfo','identifier'};
         commandFields = {'toggleOn','toggleOff','toggleQuery','amplitude','amplitudeQuery','frequency','frequencyQuery'...
            'modulationToggleOn','modulationToggleOff','modulationToggleQuery','modulationWaveform',...
            'modulationWaveformQuery','modulationType','modulationTypeQuery','modulationExternalIQ'};
         numericalFields = {'frequency','amplitude'};%has units, conversion factor, and min/max
         obj = loadConfig(obj,configFileName,configFields,commandFields,numericalFields);
      end

      function obj = connect(obj) 

         if obj.connected
            warning('RF generator is already connected')
            return
         end         

         switch lower(obj.connectionInfo.vendor)
            case {'srs','stanford'}
                obj.connectionInfo.vendor = 'srs'; %Standardization
               %Validates that config info has needed fields
               mustContainField(obj.connectionInfo,{'checkedValue','fieldToCheck'})

               %Connects to instrument from available devices
               devicesList = visadevlist;
               stanfordRow = contains(lower(devicesList.(obj.connectionInfo.fieldToCheck)),lower(obj.connectionInfo.checkedValue));
               try
               obj.handshake = visadev(devicesList.ResourceName(stanfordRow));
               catch connectionError
                   assignin("base","connectionError",connectionError)
                   error('Unable to identify RF generator.')
               end

               obj.uncommonProperties.connectionType = 'visadev';

            case {'wf','windfreak'}
                obj.connectionInfo.vendor = 'wf'; %Standardization
               %Validates that config info has needed fields
               mustContainField(obj.connectionInfo,{'comPort','baudRate'})

               %If no com port is given, check it using general function
               if isempty(obj.connectionInfo.comPort)
                  obj.connectionInfo.comPort = instrumentType.checkPort();
               end

               %Creates connection to instrument
               obj.handshake = serialport(sprintf('COM%d',obj.connectionInfo.comPort),obj.connectionInfo.baudRate);

               obj.uncommonProperties.connectionType = 'com';

               %Whenever a setting is changed for windfreak, it stalls out for ~4-5 seconds and cannot answer queries
               %This setting bypasses ordinary check that makes sure setting has changed properly
               %This does mean, however, that it may be more susceptible to errors
               obj.uncommonProperties.bypassPostCheck = true;

            otherwise
               error('Invalid vendor. Must be SRS or windfreak')
         end

         obj.connected = true;
         obj = queryFrequency(obj);
         obj = queryAmplitude(obj);
         obj = queryToggle(obj);
         obj = queryModulationToggle(obj);
         obj = queryModulationWaveform(obj);
         obj = queryModulationType(obj);
      end

      function obj = disconnect(obj)
         if ~obj.connected    
             return;   
         end
         if ~isempty(obj.handshake)
            obj.handshake = [];
         end
         obj.connected = false;
      end

      function obj = toggle(obj,setState)
         obj.enabled = setState;
      end

      function obj = modulationToggle(obj,setState)
         obj.modulationEnabled = setState;
      end
   end

   methods %Internal Functions

      function [obj,numericalData] = readNumber(obj,attributeQuery)          
          [obj,numericalData] = readInstrument(obj,attributeQuery);
         numericalData = str2double(numericalData);          
      end

      function obj = writeNumber(obj,attribute,numericalInput)          
         inputCommand = sprintf(obj.commands.(attribute),numericalInput);
         %For windfreak, a decimal is required otherwise it gives errors
         if strcmp(obj.connectionInfo.vendor,'wf')
             if ~contains(inputCommand,'.')
                 inputCommand(end+1:end+2) = '.0';
             end
         end
         obj = writeInstrument(obj,inputCommand);         
      end

      function [obj,toggleStatus] = readToggle(obj,attributeQuery)
         [obj,toggleStatus] = readInstrument(obj,attributeQuery);
      end

      function obj = writeToggle(obj,toggleCommand) 
         obj = writeInstrument(obj,toggleCommand);
         pause(.01)%Wait for RF generator to adjust
      end

      function [obj,stringOut] = readString(obj)
         [obj,stringOut] = readInstrument(obj);
      end

      function writeString(obj,stringInput)
         writeInstrument(obj,stringInput);
         pause(.01)%Wait for RF generator to adjust
      end

   end

   methods %Instrument Queries
      function obj = queryFrequency(obj)
          %Windfreak is stupid and gives different units for output than
          %for input
          if strcmp(obj.connectionInfo.vendor,'wf')
              [obj,newVal] = writeNumberProtocol(obj,'frequency','query',[],1e-3);
          else
              [obj,newVal] = writeNumberProtocol(obj,'frequency','query');
          end  
         obj.frequency = newVal;
      end

      function obj = queryAmplitude(obj)
         [obj,newVal] = writeNumberProtocol(obj,'amplitude','query');
         obj.amplitude = newVal;
      end

      function obj = queryToggle(obj)
         [obj,newVal] = writeToggleProtocol(obj,'query');
         obj.enabled = newVal;
      end

      function obj = queryModulationToggle(obj)
         %Custom input command rather than default naming convention
         modToggleCmds.toggleOn = obj.commands.modulationToggleOn;
         modToggleCmds.toggleOff = obj.commands.modulationToggleOff;
         modToggleCmds.query = obj.commands.modulationToggleQuery;
         modToggleCmds.toggleName = 'modulationEnabled';
         [obj,foundState] = writeToggleProtocol(obj,'query',modToggleCmds);
         obj.modulationEnabled = foundState;
      end

      function obj = queryModulationWaveform(obj)
         writeString(obj,obj.commands.modulationWaveformQuery)
         [obj,waveNumber] = readString(obj);
         waveNumber = s2c(waveNumber);
         switch waveNumber(1)
            case '0'
               obj.modulationWaveform = 'sine';
            case '1'
               obj.modulationWaveform = 'ramp';
            case '2'
               obj.modulationWaveform = 'triangle';
            case '3'
               obj.modulationWaveform = 'square';
            case '4'
               obj.modulationWaveform = 'noise';
            case '5'
               obj.modulationWaveform = 'external';
         end         
      end

      function [obj,modType] = queryModulationType(obj)
         writeString(obj,obj.commands.modulationTypeQuery)
         [obj,modType] = readString(obj);
         modType = s2c(modType);
         switch modType(1)
             case '0'
                 obj.modulationType = 'amplitude';
             case '6'
                 obj.modulationType = 'I/Q';
             otherwise
                 obj.modulationType = 'unknown';
         end
      end

   end

   methods %Variable Set Functions

      function set.frequency(obj,val)
          %Windfreak is stupid and gives different units for output than
          %for input         
          if strcmp(obj.connectionInfo.vendor,'wf')
              [obj,newVal] = writeNumberProtocol(obj,'frequency',val,[],1e-3);
          else
              [obj,newVal] = writeNumberProtocol(obj,'frequency',val);
          end          
          obj.frequency = newVal;     
      end

      function set.amplitude(obj,val)
         [obj,newVal] = writeNumberProtocol(obj,'amplitude',val);
          obj.amplitude = newVal;
      end

      function set.enabled(obj,val)
         [obj,foundState] = writeToggleProtocol(obj,val);
          obj.enabled = foundState;
      end

      function set.modulationEnabled(obj,val)
         modToggleCmds.toggleOn = obj.commands.modulationToggleOn; %#ok<*MCSUP>
         modToggleCmds.toggleOff = obj.commands.modulationToggleOff;
         modToggleCmds.query = obj.commands.modulationToggleQuery;
         modToggleCmds.toggleName = 'modulationEnabled';
         [obj,foundState] = writeToggleProtocol(obj,val,modToggleCmds); 
         obj.modulationEnabled = foundState;
      end

      function set.modulationType(obj,val)
         %Can theoretically resend modulation type already present by using "improper" name
         %i.e. 'i/q' when it is currently set to 'iq'. This is so minor I am not fixing it
         if strcmpi(obj.modulationType,val)
            printOut(obj,sprintf('Modulation type already %s',obj.modulationType))
            return
         end

         switch lower(val)
            case {'iq','i/q'}
               obj = writeNumber(obj,'modulationType',6);
               writeString(obj,obj.commands.modulationExternalIQ)             
            case 'amplitude'
               obj = writeNumber(obj,'modulationType',0);
            otherwise
               error('Invalid waveform type. Must be I/Q, or amplitude')
         end      
         obj.modulationType = val;
      end

      function set.modulationWaveform(obj,val)
         if strcmpi(obj.modulationWaveform,val)
            printOut(obj,sprintf('Modulation waveform already %s',val))
            return
         end
         switch lower(val)
            case {'sine','sin'}
               n = 0;
            case 'ramp'
               n = 1;
            case 'triangle'
               n = 2;
            case {'square','box'}
               n = 3;
            case 'noise'
               n = 4;
            case 'external'
               n = 5;
            otherwise
               error('Invalid waveform type. Must be sine, ramp, triangle, square, noise, or external')
         end
         obj = writeNumber(obj,'modulationWaveform',n);
         obj.modulationWaveform = val;
      end

   end

   methods (Static)
       function failCase(attribute,setState,currentState)
         error('%s read from RF generator is %g upon %g input',attribute,currentState,setState)
      end
       
   end



end