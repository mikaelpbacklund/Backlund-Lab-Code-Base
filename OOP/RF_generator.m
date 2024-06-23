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

   properties (SetAccess = protected, GetAccess = public)
      frequencyInfo
      amplitudeInfo
      commands
      handshake
   end
   
   methods
      function h = RF_generator          
%          presetNames = {'frequency','amplitude','enabled','modulationEnabled',...
%             'modulationType','modulationWaveform'};
%          h = generateDefaults(h,presetNames);
      end
      
      function h = connect(h,configName) %May also need user edits depending on instrumentation
         if h.connected
            warning('RF generator is already connected')
            return
         end
         
         %Loads config file and checks relevant field names
         configFields = {};
         commandFields = {'toggleOn','toggleOff','toggleQuery','amplitude','amplitudeQuery','frequency','frequencyQuery'...
            'modulationToggleOn','modulationToggleOff','modulationToggleQuery','modulationWaveform',...
            'modulationWaveformQuery','modulationType','modulationTypeQuery','modulationExternalIQ'};
         numericalFields = {'frequency','amplitude'};%has units, conversion factor, and min/max         
         h = loadConfig(h,configName,configFields,commandFields,numericalFields);
         
         %What should be identified to determine which visadev is the RF
         %generator. May need changing
         fieldToCheck = "Vendor";
         checkField = "Stanford";
         
         %Connects to instrument from available devices
         devicesList = visadevlist;        
         stanfordRow = contains(devicesList.(fieldToCheck),checkField);
         h.handshake = visadev(devicesList.ResourceName(stanfordRow));
         fopen(h.handshake);
         
         h.connected = true;
         h = checkPresets(h);         
      end
      
      %% Internal Functions
      
      function [h,numericalData] = readNumber(h,attributeQuery)         
         fprintf(h.handshake,attributeQuery);
         numericalData = str2double(fscanf(h.handshake));
      end
      
      function h = writeNumber(h,attribute,numericalInput)
         inputCommand = sprintf(h.commands.(attribute),numericalInput);
         fprintf(h.handshake,inputCommand);
      end
      
      function [h,toggleStatus] = readToggle(h,attributeQuery)
         %Readout from instrument is a character array beginning with
         %0 or 1 depending on whether it is off or on
         fprintf(h.handshake,attributeQuery);
         toggleStatus = fscanf(h.handshake);
         toggleStatus = toggleStatus(1);
      end
      
      function h = writeToggle(h,toggleCommand)
         fprintf(h.handshake,toggleCommand);
      end
      
      function stringOut = readString(h)
         stringOut = fscanf(h.handshake);
      end
      
      function writeString(h,stringInput)
         fprintf(h.handshake,stringInput);
      end
      
       function h = checkPresets(h)
         %Checks if preset values exist and queries/sets them as
         %appropriate
         
         %It is more trouble than it is worth to try to automate this more.
         %I would have to do some very specific naming conventions or weird
         %work-arounds.
         if isempty(h.presets.frequency)
            h = queryFrequency(h);
         else
            h = setFrequency(h,h.presets.frequency);
         end
         if isempty(h.presets.amplitude)
            h = queryAmplitude(h);
         else
            h = setAmplitude(h,h.presets.amplitude);
         end
         if isempty(h.presets.enabled)
            h = queryToggle(h);
         else
            h = toggle(h,h.presets.enabled);
         end

         if isempty(h.presets.modulationEnabled)
            h = queryModulationToggle(h);
         else
            h = modulationToggle(h,h.presets.modulationEnabled);
         end
         if isempty(h.presets.modulationType)
            h = queryModulationType(h);
         else
            h = setModulationType(h,h.presets.modulationType);
         end
         if isempty(h.presets.modulationWaveform)
            h = queryModulationWaveform(h);
         else
            h = setModulationWaveform(h,h.presets.modulationWaveform);
         end
      end
      
   end

   %% User Functions
      methods      
      function h = queryFrequency(h)
         h = writeNumberProtocol(h,'frequency','query');
      end
      
      function h = setFrequency(h,inputFrequency)
         mustBeNumeric(inputFrequency)
         h = writeNumberProtocol(h,'frequency',inputFrequency);
      end
      
      function h = queryAmplitude(h)
         h = writeNumberProtocol(h,'amplitude','query');
      end
      
      function h = setAmplitude(h,inputAmplitude)
         mustBeNumeric(inputAmplitude)
         h = writeNumberProtocol(h,'amplitude',inputAmplitude);
      end
      
      function h = queryToggle(h)
         h = writeToggleProtocol(h,'query');
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

      %% Set/Get Functions
      methods 

         % function set.frequency(h,val)
         % 
         % end
         % 
         % function val = get.frequency(h)
         % 
         % end

      end
   
   methods (Static)
      function failCase(attribute,currentState,setState)
         error('%s read from RF generator is %g upon %g input',attribute,currentState,setState)
      end
   end
   
   
   
end