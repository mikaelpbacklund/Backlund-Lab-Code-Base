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

      function h = RF_generator(configFileName)

          if nargin < 1
              error('Config file name required as input')
          end

         %Loads config file and checks relevant field names
         configFields = {'connectionInfo','identifier'};
         commandFields = {'toggleOn','toggleOff','toggleQuery','amplitude','amplitudeQuery','frequency','frequencyQuery'...
            'modulationToggleOn','modulationToggleOff','modulationToggleQuery','modulationWaveform',...
            'modulationWaveformQuery','modulationType','modulationTypeQuery','modulationExternalIQ'};
         numericalFields = {'frequency','amplitude'};%has units, conversion factor, and min/max
         h = loadConfig(h,configFileName,configFields,commandFields,numericalFields);
      end

      function h = connect(h) 

         if h.connected
            warning('RF generator is already connected')
            return
         end         

         switch lower(h.connectionInfo.vendor)
            case {'srs','stanford'}
                h.connectionInfo.vendor = 'srs'; %Standardization
               %Validates that config info has needed fields
               mustContainField(h.connectionInfo,{'checkedValue','fieldToCheck'})

               %Connects to instrument from available devices
               devicesList = visadevlist;
               stanfordRow = contains(lower(devicesList.(h.connectionInfo.fieldToCheck)),lower(h.connectionInfo.checkedValue));
               try
               h.handshake = visadev(devicesList.ResourceName(stanfordRow));
               catch connectionError
                   assignin("base","connectionError",connectionError)
                   error('Unable to identify RF generator.')
               end

               h.uncommonProperties.connectionType = 'visadev';

            case {'wf','windfreak'}
                h.connectionInfo.vendor = 'wf'; %Standardization
               %Validates that config info has needed fields
               mustContainField(h.connectionInfo,{'comPort','baudRate'})

               %If no com port is given, check it using general function
               if isempty(h.connectionInfo.comPort)
                  h.connectionInfo.comPort = instrumentType.checkPort();
               end

               %Creates connection to instrument
               h.handshake = serialport(sprintf('COM%d',h.connectionInfo.comPort),h.connectionInfo.baudRate);

               h.uncommonProperties.connectionType = 'com';

               %Whenever a setting is changed for windfreak, it stalls out for ~4-5 seconds and cannot answer queries
               %This setting bypasses ordinary check that makes sure setting has changed properly
               %This does mean, however, that it may be more susceptible to errors
               h.uncommonProperties.bypassPostCheck = true;

            otherwise
               error('Invalid vendor. Must be SRS or windfreak')
         end

         h.connected = true;
         h = queryFrequency(h);
         h = queryAmplitude(h);
         h = queryToggle(h);
         h = queryModulationToggle(h);
         h = queryModulationWaveform(h);
         h = queryModulationType(h);
      end

      function h = disconnect(h)
         if ~h.connected    
             return;   
         end
         if ~isempty(h.handshake)
            h.handshake = [];
         end
         h.connected = false;
      end

      function h = toggle(h,setState)
         h.enabled = setState;
      end

      function h = modulationToggle(h,setState)
         h.modulationEnabled = setState;
      end
   end

   methods %Internal Functions

      function [h,numericalData] = readNumber(h,attributeQuery)          
          [h,numericalData] = readInstrument(h,attributeQuery);
         numericalData = str2double(numericalData);          
      end

      function h = writeNumber(h,attribute,numericalInput)          
         inputCommand = sprintf(h.commands.(attribute),numericalInput);
         %For windfreak, a decimal is required otherwise it gives errors
         if strcmp(h.connectionInfo.vendor,'wf')
             if ~contains(inputCommand,'.')
                 inputCommand(end+1:end+2) = '.0';
             end
         end
         h = writeInstrument(h,inputCommand);         
      end

      function [h,toggleStatus] = readToggle(h,attributeQuery)
         [h,toggleStatus] = readInstrument(h,attributeQuery);
      end

      function h = writeToggle(h,toggleCommand) 
         h = writeInstrument(h,toggleCommand);
         pause(.01)%Wait for RF generator to adjust
      end

      function [h,stringOut] = readString(h)
         [h,stringOut] = readInstrument(h);
      end

      function writeString(h,stringInput)
         writeInstrument(h,stringInput);
         pause(.01)%Wait for RF generator to adjust
      end

   end

   methods %Instrument Queries
      function h = queryFrequency(h)
          %Windfreak is stupid and gives different units for output than
          %for input
          if strcmp(h.connectionInfo.vendor,'wf')
              [h,newVal] = writeNumberProtocol(h,'frequency','query',[],1e-3);
          else
              [h,newVal] = writeNumberProtocol(h,'frequency','query');
          end  
         h.frequency = newVal;
      end

      function h = queryAmplitude(h)
         [h,newVal] = writeNumberProtocol(h,'amplitude','query');
         h.amplitude = newVal;
      end

      function h = queryToggle(h)
         [h,newVal] = writeToggleProtocol(h,'query');
         h.enabled = newVal;
      end

      function h = queryModulationToggle(h)
         %Custom input command rather than default naming convention
         modToggleCmds.toggleOn = h.commands.modulationToggleOn;
         modToggleCmds.toggleOff = h.commands.modulationToggleOff;
         modToggleCmds.query = h.commands.modulationToggleQuery;
         modToggleCmds.toggleName = 'modulationEnabled';
         [h,foundState] = writeToggleProtocol(h,'query',modToggleCmds);
         h.modulationEnabled = foundState;
      end

      function h = queryModulationWaveform(h)
         writeString(h,h.commands.modulationWaveformQuery)
         [h,waveNumber] = readString(h);
         waveNumber = s2c(waveNumber);
         switch waveNumber(1)
            case '0'
               h.modulationWaveform = 'sine';
            case '1'
               h.modulationWaveform = 'ramp';
            case '2'
               h.modulationWaveform = 'triangle';
            case '3'
               h.modulationWaveform = 'square';
            case '4'
               h.modulationWaveform = 'noise';
            case '5'
               h.modulationWaveform = 'external';
         end         
      end

      function [h,modType] = queryModulationType(h)
         writeString(h,h.commands.modulationTypeQuery)
         [h,modType] = readString(h);
         modType = s2c(modType);
         switch modType(1)
             case '0'
                 h.modulationType = 'amplitude';
             case '6'
                 h.modulationType = 'I/Q';
             otherwise
                 h.modulationType = 'unknown';
         end
      end

   end

   methods %Variable Set Functions

      function set.frequency(h,val)
          %Windfreak is stupid and gives different units for output than
          %for input         
          if strcmp(h.connectionInfo.vendor,'wf')
              [h,newVal] = writeNumberProtocol(h,'frequency',val,[],1e-3);
          else
              [h,newVal] = writeNumberProtocol(h,'frequency',val);
          end          
          h.frequency = newVal;     
      end

      function set.amplitude(h,val)
         [h,newVal] = writeNumberProtocol(h,'amplitude',val);
          h.amplitude = newVal;
      end

      function set.enabled(h,val)
         [h,foundState] = writeToggleProtocol(h,val);
          h.enabled = foundState;
      end

      function set.modulationEnabled(h,val)
         modToggleCmds.toggleOn = h.commands.modulationToggleOn; %#ok<*MCSUP>
         modToggleCmds.toggleOff = h.commands.modulationToggleOff;
         modToggleCmds.query = h.commands.modulationToggleQuery;
         modToggleCmds.toggleName = 'modulationEnabled';
         [h,foundState] = writeToggleProtocol(h,val,modToggleCmds); 
         h.modulationEnabled = foundState;
      end

      function set.modulationType(h,val)
         %Can theoretically resend modulation type already present by using "improper" name
         %i.e. 'i/q' when it is currently set to 'iq'. This is so minor I am not fixing it
         if strcmpi(h.modulationType,val)
            printOut(h,sprintf('Modulation type already %s',h.modulationType))
            return
         end

         switch lower(val)
            case {'iq','i/q'}
               h = writeNumber(h,'modulationType',6);
               writeString(h,h.commands.modulationExternalIQ)             
            case 'amplitude'
               h = writeNumber(h,'modulationType',0);
            otherwise
               error('Invalid waveform type. Must be I/Q, or amplitude')
         end      
         h.modulationType = val;
      end

      function set.modulationWaveform(h,val)
         if strcmpi(h.modulationWaveform,val)
            printOut(h,sprintf('Modulation waveform already %s',val))
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
         h = writeNumber(h,'modulationWaveform',n);
         h.modulationWaveform = val;
      end

   end

   methods (Static)
       function failCase(attribute,setState,currentState)
         error('%s read from RF generator is %g upon %g input',attribute,currentState,setState)
      end
       
   end



end