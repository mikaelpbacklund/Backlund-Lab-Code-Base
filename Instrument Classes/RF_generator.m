classdef RF_generator < instrumentType
    % RF_GENERATOR Controls and interfaces with RF signal generator instruments
    %   This class provides a unified interface for controlling various RF signal 
    %   generator instruments, including Stanford Research Systems (SRS) and 
    %   Windfreak devices. It supports configuration and control of:
    %   - Frequency and amplitude settings
    %   - Output enable/disable
    %   - Modulation settings (type, waveform, enable/disable)
    %
    % The class handles vendor-specific implementations while providing a 
    % consistent interface to the user.
    %
    % Example:
    %   rf = RF_generator('config.json');  % Create instance with config file
    %   rf.connect();                      % Establish connection
    %   rf.frequency = 1e6;                % Set frequency to 1 MHz
    %   rf.amplitude = -10;                % Set amplitude in dBm
    %   rf.enabled = true;                 % Enable RF output
    %
    % See also instrumentType
    
   properties
      enabled          % Logical indicating if RF output is enabled
      frequency        % Current frequency setting in Hz
      amplitude        % Current amplitude setting in dBm
      modulationEnabled    % Logical indicating if modulation is enabled
      modulationType      % Type of modulation ('amplitude' or 'I/Q')
      modulationWaveform  % Modulation waveform type ('sine', 'ramp', etc.)
   end

   properties (SetAccess = {?RF_generator_beta ?instrumentType}, GetAccess = public)
      %Read-only properties
      frequencyInfo      % Structure containing frequency limits and units
      amplitudeInfo      % Structure containing amplitude limits and units
      commands           % Structure containing instrument-specific commands
      handshake         % Communication handle for the instrument
      connectionInfo    % Structure containing connection parameters
   end

   methods %Misc
      function obj = RF_generator(configFileName)
          % Constructor for RF generator object
          %   OBJ = RF_GENERATOR(configFileName) initializes with config file
          
          if nargin < 1
              error('Config file name required as input')
          end

         configFields = {'connectionInfo','identifier'};
         commandFields = {'toggleOn','toggleOff','toggleQuery','amplitude','amplitudeQuery','frequency','frequencyQuery'...
            'modulationToggleOn','modulationToggleOff','modulationToggleQuery','modulationWaveform',...
            'modulationWaveformQuery','modulationType','modulationTypeQuery','modulationExternalIQ'};
         numericalFields = {'frequency','amplitude'};%has units, conversion factor, and min/max
         obj = loadConfig(obj,configFileName,configFields,commandFields,numericalFields);
      end

      function obj = connect(obj)
          % Connect to RF generator using config settings
          %   Supports SRS (VISA) and Windfreak (serial) devices
          
          try
              if obj.connected
                  warning('RF generator is already connected')
                  return
              end         

              % Save initial state before connection attempt
              obj.saveState();

              switch lower(obj.connectionInfo.vendor)
                  case {'srs','stanford'}
                      obj.connectionInfo.vendor = 'srs'; % Standardization
                      % Validates that config info has needed fields
                      mustContainField(obj.connectionInfo,{'checkedValue','fieldToCheck'})

                      % Connects to instrument from available devices
                      devicesList = visadevlist;
                      stanfordRow = contains(lower(devicesList.(obj.connectionInfo.fieldToCheck)),lower(obj.connectionInfo.checkedValue));
                      try
                          obj.handshake = visadev(devicesList.ResourceName(stanfordRow));
                      catch connectionError
                          obj.logError(connectionError, struct('vendor', 'srs', 'devicesList', devicesList));
                          error('Unable to identify RF generator.')
                      end

                      obj.uncommonProperties.connectionType = 'visadev';

                  case {'wf','windfreak'}
                      obj.connectionInfo.vendor = 'wf'; % Standardization
                      % Validates that config info has needed fields
                      mustContainField(obj.connectionInfo,{'comPort','baudRate'})

                      % If no com port is given, check it using general function
                      if isempty(obj.connectionInfo.comPort)
                          obj.connectionInfo.comPort = instrumentType.checkPort();
                      end

                      % Creates connection to instrument
                      obj.handshake = serialport(sprintf('COM%d',obj.connectionInfo.comPort),obj.connectionInfo.baudRate);

                      obj.uncommonProperties.connectionType = 'com';

                      % Whenever a setting is changed for windfreak, it stalls out for ~4-5 seconds and cannot answer queries
                      % This setting bypasses ordinary check that makes sure setting has changed properly
                      % This does mean, however, that it may be more susceptible to errors
                      obj.uncommonProperties.bypassPostCheck = true;

                  otherwise
                      error('Invalid vendor. Must be SRS or windfreak')
              end

              obj.connected = true;

              % Query initial states
              obj = queryFrequency(obj);
              obj = queryAmplitude(obj);
              obj = queryToggle(obj);
              obj = queryModulationToggle(obj);
              obj = queryModulationWaveform(obj);
              obj = queryModulationType(obj);

          catch connectErr
              % Log error with connection state
              currentState = struct(...
                  'vendor', obj.connectionInfo.vendor, ...
                  'connected', obj.connected, ...
                  'connectionType', obj.uncommonProperties.connectionType);
              obj.logError(connectErr, currentState);
              rethrow(connectErr);
          end
      end

      function obj = disconnect(obj)
          % Close connection to RF generator
          
         if ~obj.connected    
             return;   
         end
         if ~isempty(obj.handshake)
            obj.handshake = [];
         end
         obj.connected = false;
      end

      function obj = toggle(obj,setState)
          % Enable/disable RF output
          %   toggle(obj, setState) where setState is logical
          
         obj.enabled = setState;
      end

      function obj = modulationToggle(obj,setState)
          % Enable/disable modulation
          %   modulationToggle(obj, setState) where setState is logical
          
         obj.modulationEnabled = setState;
      end
   end

   methods %Internal Functions
      function [obj,numericalData] = readNumber(obj,attributeQuery)
          % Read numerical value from instrument
          %   [obj,val] = readNumber(obj,query)
          
          [obj,numericalData] = readInstrument(obj,attributeQuery);
         numericalData = str2double(numericalData);          
      end

      function obj = writeNumber(obj,attribute,numericalInput)
          % Write numerical value to instrument
          %   Handles Windfreak decimal point requirement
          
         inputCommand = sprintf(obj.commands.(attribute),numericalInput);
         if strcmp(obj.connectionInfo.vendor,'wf')
             if ~contains(inputCommand,'.')
                 inputCommand(end+1:end+2) = '.0';
             end
         end
         obj = writeInstrument(obj,inputCommand);         
      end

      function [obj,toggleStatus] = readToggle(obj,attributeQuery)
          % Read toggle state from instrument
          
         [obj,toggleStatus] = readInstrument(obj,attributeQuery);
      end

      function obj = writeToggle(obj,toggleCommand)
          % Write toggle command to instrument
          
         obj = writeInstrument(obj,toggleCommand);
         pause(.01)%Wait for RF generator to adjust
      end

      function [obj,stringOut] = readString(obj)
          % Read raw string from instrument
          
         [obj,stringOut] = readInstrument(obj);
      end

      function writeString(obj,stringInput)
          % Write raw string to instrument
          
         writeInstrument(obj,stringInput);
         pause(.01)%Wait for RF generator to adjust
      end
   end

   methods %Instrument Queries
      function obj = queryFrequency(obj)
          % Query current frequency
          %   Handles Windfreak unit conversion (1e-3)
          
          if strcmp(obj.connectionInfo.vendor,'wf')
              [obj,newVal] = writeNumberProtocol(obj,'frequency','query',[],1e-3);
          else
              [obj,newVal] = writeNumberProtocol(obj,'frequency','query');
          end  
         obj.frequency = newVal;
      end

      function obj = queryAmplitude(obj)
          % Query current amplitude
          
         [obj,newVal] = writeNumberProtocol(obj,'amplitude','query');
         obj.amplitude = newVal;
      end

      function obj = queryToggle(obj)
          % Query RF output state
          
         [obj,newVal] = writeToggleProtocol(obj,'query');
         obj.enabled = newVal;
      end

      function obj = queryModulationToggle(obj)
          % Query modulation state
          
         modToggleCmds.toggleOn = obj.commands.modulationToggleOn;
         modToggleCmds.toggleOff = obj.commands.modulationToggleOff;
         modToggleCmds.query = obj.commands.modulationToggleQuery;
         modToggleCmds.toggleName = 'modulationEnabled';
         [obj,foundState] = writeToggleProtocol(obj,'query',modToggleCmds);
         obj.modulationEnabled = foundState;
      end

      function obj = queryModulationWaveform(obj)
          % Query modulation waveform type
          %   Types: sine(0), ramp(1), triangle(2), square(3), noise(4), external(5)
          
          try
              writeString(obj,obj.commands.modulationWaveformQuery);
              [obj,waveNumber] = readString(obj);
              waveNumber = s2c(waveNumber);
              
              % Save state before processing response
              obj.saveState();
              
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
                  otherwise
                      error('Invalid waveform response: %s', waveNumber);
              end
          catch waveErr
              % Log error with current modulation state
              currentState = struct(...
                  'modulationWaveform', obj.modulationWaveform, ...
                  'response', waveNumber);
              obj.logError(waveErr, currentState);
              
              % Attempt recovery
              if ~obj.recoverState()
                  warning('Failed to recover modulation waveform state');
              end
              rethrow(waveErr);
          end
      end

      function [obj,modType] = queryModulationType(obj)
          % Query modulation type
          %   Types: amplitude(0), I/Q(6)
          
          try
              % Save state before query
              obj.saveState();
              
              writeString(obj,obj.commands.modulationTypeQuery);
              [obj,modType] = readString(obj);
              modType = s2c(modType);
              
              switch modType(1)
                  case '0'
                      obj.modulationType = 'amplitude';
                  case '6'
                      obj.modulationType = 'I/Q';
                  otherwise
                      obj.modulationType = 'unknown';
                      warning('Unexpected modulation type response: %s', modType);
              end
          catch typeErr
              % Log error with current modulation state
              currentState = struct(...
                  'modulationType', obj.modulationType, ...
                  'response', modType);
              obj.logError(typeErr, currentState);
              
              % Attempt recovery
              if ~obj.recoverState()
                  warning('Failed to recover modulation type state');
              end
              rethrow(typeErr);
          end
      end
   end

   methods %Variable Set Functions
      function set.frequency(obj,val)
          % Set RF frequency (Hz)
          %   Handles Windfreak unit conversion (different for input and output)
          
          if strcmp(obj.connectionInfo.vendor,'wf')
              [obj,newVal] = writeNumberProtocol(obj,'frequency',val,[],1e-3);
          else
              [obj,newVal] = writeNumberProtocol(obj,'frequency',val);
          end          
          obj.frequency = newVal;     
      end

      function set.amplitude(obj,val)
          % Set RF amplitude (dBm)
          
         [obj,newVal] = writeNumberProtocol(obj,'amplitude',val);
          obj.amplitude = newVal;
      end

      function set.enabled(obj,val)
          % Set RF output state (logical)
          
         [obj,foundState] = writeToggleProtocol(obj,val);
          obj.enabled = foundState;
      end

      function set.modulationEnabled(obj,val)
          % Set modulation state (logical)
          
         modToggleCmds.toggleOn = obj.commands.modulationToggleOn; %#ok<*MCSUP>
         modToggleCmds.toggleOff = obj.commands.modulationToggleOff;
         modToggleCmds.query = obj.commands.modulationToggleQuery;
         modToggleCmds.toggleName = 'modulationEnabled';
         [obj,foundState] = writeToggleProtocol(obj,val,modToggleCmds); 
         obj.modulationEnabled = foundState;
      end

      function set.modulationType(obj,val)
          % Set modulation type
          %   Valid types: 'iq'/'i/q'(6) or 'amplitude'(0)
          
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
          % Set modulation waveform
          %   Types: sine/sin(0), ramp(1), triangle(2), square/box(3), 
          %         noise(4), external(5)
          
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
           % Throw error when set operation fails
           %   failCase(attribute, setState, currentState)
           
         error('%s read from RF generator is %g upon %g input',attribute,currentState,setState)
      end
   end



end