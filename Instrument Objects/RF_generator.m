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

   methods %Internal Functions

      function [h,numericalData] = readNumber(h,attributeQuery)
          [h,numericalData] = readInstrument(h,attributeQuery);
         numericalData = str2double(numericalData); 
      end

      function h = writeNumber(h,attribute,numericalInput)
         inputCommand = sprintf(h.commands.(attribute),numericalInput);
         h = writeInstrument(h,inputCommand);
         pause(.01)%Wait for RF generator to adjust
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

   methods %User Functions

      function h = connect(h,configName) 
         if h.connected
            warning('RF generator is already connected')
            return
         end

         %Loads config file and checks relevant field names
         configFields = {'connectionInfo'};
         commandFields = {'toggleOn','toggleOff','toggleQuery','amplitude','amplitudeQuery','frequency','frequencyQuery'...
            'modulationToggleOn','modulationToggleOff','modulationToggleQuery','modulationWaveform',...
            'modulationWaveformQuery','modulationType','modulationTypeQuery','modulationExternalIQ'};
         numericalFields = {'frequency','amplitude'};%has units, conversion factor, and min/max
         h = loadConfig(h,configName,configFields,commandFields,numericalFields);

         switch lower(h.connectionInfo.vendor)
            case {'srs','stanford'}
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
               try
               fopen(h.handshake);
               catch connectionError
                   assignin("base","connectionError",connectionError)
                   error('Unable to form connection to RF generator.')
               end

               h.connectionType = 'serialport';
               h.identifier = 'SRS RF';

            case {'wf','windfreak'}
               %Validates that config info has needed fields
               mustContainField(h.connectionInfo,{'comPort','baudRate'})

               %If no com port is given, check it using general function
               if isempty(h.connectionInfo.comPort)
                  h.connectionInfo.comPort = instrumentType.checkPort();
               end

               %Creates connection to instrument
               h.handshake = serialport(sprintf('COM%d',h.connectionInfo.comPort),h.connectionInfo.baudRate);

               h.connectionType = 'com';
               h.identifier = 'windfreak RF';

            otherwise
               error('Invalid vendor. Must be SRS or windfreak')
         end

         h.connected = true;
         h = queryFrequency(h);
         h = queryAmplitude(h);
         h = queryToggle(h);
      end

      function h = queryFrequency(h)
         [h,newVal] = writeNumberProtocol(h,'frequency','query');
         h.frequency = newVal;
      end

      function h = setFrequency(h,inputFrequency)
         [h,newVal] = writeNumberProtocol(h,'frequency',inputFrequency);
         h.frequency = newVal;
      end

      function h = queryAmplitude(h)
         [h,newVal] = writeNumberProtocol(h,'amplitude','query');
         h.amplitude = newVal;
      end

      function h = setAmplitude(h,inputAmplitude)
         h = writeNumberProtocol(h,'amplitude',inputAmplitude);
      end

      function h = queryToggle(h)
         [h,newVal] = writeToggleProtocol(h,'query');
         h.enabled = newVal;
      end

      function h = toggle(h,setState)
         h = writeToggleProtocol(h,setState);
      end

      function h = queryModulationToggle(h)
         %Custom input command rather than default naming convention
         modToggleCmds.toggleOn = h.commands.modulationToggleOn;
         modToggleCmds.toggleOff = h.commands.modulationToggleOff;
         modToggleCmds.query = h.commands.modulationToggleQuery;
         modToggleCmds.toggleName = 'modulationEnabled';
         h = writeToggleProtocol(h,'query',modToggleCmds);
      end

      function h = modulationToggle(h,setState)
         %Custom input command rather than default naming convention
         modToggleCmds.toggleOn = h.commands.modulationToggleOn;
         modToggleCmds.toggleOff = h.commands.modulationToggleOff;
         modToggleCmds.query = h.commands.modulationToggleQuery;
         modToggleCmds.toggleName = 'modulationEnabled';
         h = writeToggleProtocol(h,setState,modToggleCmds);
      end

      function h = queryModulationWaveform(h)
         writeString(h,h.commands.modulationWaveformQuery)
         waveNumber = readString(h);
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

      function h = setModulationWaveform(h,setState)
         h = queryModulationWaveform(h);
         if strcmpi(h.modulationWaveform,setState)
            printOut(h,sprintf('Modulation waveform already %s',setState))
            return
         end

         switch lower(setState)
            case 'sine'
               n = 0;
            case 'ramp'
               n = 1;
            case 'triangle'
               n = 2;
            case 'square'
               n = 3;
            case 'noise'
               n = 4;
            case 'external'
               n = 5;
            otherwise
               error('Invalid waveform type. Must be sine, ramp, triangle, square, noise, or external')
         end
         h = writeNumber(h,'modulationWaveform',n);
         h.modulationWaveform = setState;
      end

      function h = queryModulationType(h)
         writeString(h,h.commands.modulationTypeQuery)
         modType = readString(h);
         switch modType(1)
            case '0'
               h.modulationType = 'amplitude';
            case '6'
               h.modulationType = 'I/Q';
            otherwise
               h.modulationType = 'unknown';
         end
      end

      function h = setModulationType(h,setState)
         h = queryModulationType(h);
         if strcmpi(setState,'iq')
            setState = 'I/Q';
         end
         if strcmpi(h.modulationType,setState)
            printOut(h,sprintf('Modulation type already %s',setState))
            return
         end
         switch lower(setState)
            case 'i/q'
               h = writeNumber(h,'modulationType',6);
               writeString(h,h.commands.modulationExternalIQ)
            case 'amplitude'
               h = writeNumber(h,'modulationType',0);
            otherwise
               error('Invalid waveform type. Must be I/Q, or amplitude')
         end
         h.modulationType = setState;
      end

   end

   methods %Variable Set Functions

      function set.frequency(h,val)
          [h,newVal] = writeNumberProtocol(h,'frequency',val);
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
         h = modulationToggle(h,val); %#ok<NASGU>
      end

      function set.modulationType(h,val)
         h = setModulationType(h,val); %#ok<NASGU>
      end

      function set.modulationWaveform(h,val)
         h = setModulationWaveform(h,val); %#ok<NASGU>
      end

   end

   methods (Static)
      function failCase(attribute,currentState,setState)
         error('%s read from RF generator is %g upon %g input',attribute,currentState,setState)
      end
   end



end