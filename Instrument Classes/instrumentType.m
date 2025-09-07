classdef instrumentType < handle
    %INSTRUMENTTYPE Base class for laboratory instrument control
    %   Provides core functionality for instrument communication, configuration,
    %   and error handling. This class serves as the foundation for specific
    %   instrument implementations.
    %
    % Key Features:
    %   - Unified interface for different connection types (VISA, Serial, COM)
    %   - Configuration management and validation
    %   - Error logging and state recovery
    %   - Parameter bounds checking
    %
    % Common Usage:
    %   Inherit from this class to create specific instrument classes:
    %   classdef MyInstrument < instrumentType
    %       % Implement instrument-specific functionality
    %   end
    %
    % Error Handling:
    %   - Automatic logging of errors to file and memory
    %   - State preservation before risky operations
    %   - Automatic recovery attempts after failures
    %
    % Configuration:
    %   - Loads settings from config files
    %   - Supports default values and presets
    %   - Validates required parameters
    %
    %#ok<*MCNPN>
    % Removes warnings from properties that are not defined in this class

    % See also: 
    % RF_generator - RF signal generator control
    % laser - Laser device control
    % DAQ_controller - Data acquisition device control
    % stage - Motion stage control
    % pulse_blaster - Pulse sequence generator
    % cam - Camera control
    % kinesis_piezo - Piezo controller
    % deformable_mirror - Mirror control system
    

   properties      
      uncommonProperties  % Rarely accessed properties to reduce clutter
      notifications = false  % Enable/disable status messages
      presets  % User-defined instrument settings
   end

   properties (SetAccess = protected, GetAccess = public)
      defaults  % Default instrument settings
      connected = false  % Connection status
      identifier  % Unique instrument identifier
      errorLog  % History of errors and states
   end

   properties (Constant, Hidden)
      maxLogSize = 100  % Maximum number of errors to keep in log
      logFileName = 'instrument_error_log.txt'  % File to save error logs
   end

   methods
      function obj = instrumentType
          % Initialize instrument object with default settings
          
          obj.uncommonProperties.connectionType = [];
          obj.uncommonProperties.bypassPreCheck = false;
          obj.uncommonProperties.bypassPostCheck = false;
          obj.errorLog = struct('timestamp', {}, 'error', {}, 'state', {});
      end
      
      function printOut(obj,printMessage)
          % Display status message if notifications enabled
          
          if obj.notifications
              fullMessage = sprintf('%s\n',printMessage);
              fprintf(fullMessage)
          end
      end

      function s = checkSettings(obj,propertyNames)
          % Get property values from presets or defaults
          %   Returns current value, preset, or default in that order
          
          mustBeA(propertyNames,["char","string","cell"])         
          p = string(propertyNames);
          
          % Check priority: current value -> preset -> default
          for ii = 1:numel(p)
              m = p(ii);
              % Return existing value if present
              if isprop(obj,m) && ~isempty(obj.(m))
                  s.(m) = obj.(m);
                  continue
              end
              
              % Check presets if no current value
              if isprop(obj,'presets') && isfield(obj.presets,m) && ~isempty(obj.presets.(m))
                  s.(m) = obj.presets.(m);
                  continue
              end
              
              % Use default if nothing else available
              if isprop(obj,'defaults') && isfield(obj.defaults,m) && ~isempty(obj.defaults.(m))
                  s.(m) = obj.defaults.(m);
              else
                  s.(m) = [];
                  warning('%s property within %s checked for preset/default but neither was present',m,class(obj))
              end            
          end
          
          % Return direct value instead of struct for single property
          if isscalar(fieldnames(s))
              s = s.(m);
          end
      end
      
      function checkConnection(obj)
          % Verify instrument is connected before operations
          
          try
              if isempty(obj.connected) || ~obj.connected
                  error('Connection must be established to instrument to execute this function')
              end
          catch connErr
              currentState = struct('connected', obj.connected);
              obj.logError(obj,connErr, currentState);
              rethrow(connErr);
          end
      end

      function shouldChange = changeNeeded(obj,setState,attribute,minimumAttribute,maximumAttribute)
          % Check if parameter change is needed and within bounds
          
          if ~isa(setState,'double')
              shouldChange = false;
              return
          end
          
          if setState == obj.(attribute)
              printOut(obj,sprintf('%s already %g',attribute,obj.(attribute)))
              shouldChange = false;
              return
          end
          
          if obj.(minimumAttribute) < setState && setState <= obj.(maximumAttribute)
              shouldChange = true;
              return
          else
              error('%s input must be between %g and %g',...
                  obj.(attribute),obj.(minimumAttribute),obj.(maximumAttribute))
          end
      end
      
      function [obj,updatedVal] = writeNumberProtocol(obj,attribute,setState,varargin)
          % Write numerical value to instrument with validation
          %   Handles unit conversion and bounds checking
          
          checkConnection(obj)
          if ~strcmp(setState,'query') && ~isa(setState,'double') 
              error('Write number input must be double or the string "query"')
          end
          
          % Allow custom attribute info or use standard naming convention
          if nargin > 3 && ~isempty(varargin{1})
              attributeInfo = varargin{1};
          end
          
          % Get attribute info using standard naming or override
          if ~exist('attributeInfo','var') || ~isfield(attributeInfo,'query')
              attributeInfo.query = obj.commands.(strcat(attribute,'Query')); 
          end
          attInfoStr = strcat(attribute,'Info');
          if ~isfield(attributeInfo,'conversionFactor')
              attributeInfo.conversionFactor = obj.(attInfoStr).('conversionFactor'); % Multiply when writing, divide when reading
          end
          if ~isfield(attributeInfo,'minimum')
              attributeInfo.minimum = obj.(attInfoStr).('minimum');
          end
          if ~isfield(attributeInfo,'maximum')
              attributeInfo.maximum = obj.(attInfoStr).('maximum');
          end
          if ~isfield(attributeInfo,'units')
              attributeInfo.units = obj.(attInfoStr).('units');
          end
          if ~isfield(attributeInfo,'tolerance')
              if isfield(obj.(attribute),'tolerance')
                  attributeInfo.tolerance = obj.attInfoStr.('tolerance');
              else
                  attributeInfo.tolerance = abs(setState)*.00001; % Default 0.001% tolerance
              end        
          end

          % Pre-write validation unless bypassed
          if ~obj.uncommonProperties.bypassPreCheck || strcmpi(setState,'query') 
              [obj,numericalData] = readNumber(obj,attributeInfo.query);
              
              % Handle unit conversion for special cases (e.g., Windfreak)
              if nargin > 4 && ~isempty(varargin{2})
                  numericalData = numericalData * varargin{2};
              end
              updatedVal = numericalData./attributeInfo.conversionFactor;

              % Return early if just querying
              if strcmpi(setState,'query')
                  return
              end   

              % Skip if value already correct within tolerance
              if setState <= updatedVal + attributeInfo.tolerance && setState >=updatedVal - attributeInfo.tolerance %#ok<BDSCI>
                  printOut(obj,sprintf('%s already %g %s',attribute,updatedVal,attributeInfo.units))
                  return
              end                     
          end         
          
          % Validate bounds and write new value
          if attributeInfo.minimum <= setState && setState <= attributeInfo.maximum
              numericalInput = setState*attributeInfo.conversionFactor;
              obj = writeNumber(obj,attribute,numericalInput);
          else
              error('%s must be between %g and %g %s (%g given)',...
                  attribute,attributeInfo.minimum,attributeInfo.maximum,attributeInfo.units,setState)
          end
          
          % Skip post-write validation if bypassed
          if obj.uncommonProperties.bypassPostCheck
              updatedVal = setState;
              return
          end
          
          % Verify write operation succeeded
          [obj,numericalData] = readNumber(obj,attributeInfo.query);

          % Handle special unit conversion cases
          if nargin > 4 && ~isempty(varargin{2})
              numericalData = numericalData * varargin{2};
          end
          
          % Validate write succeeded within tolerance
          if numericalData > numericalInput + attributeInfo.tolerance || numericalData < numericalInput - attributeInfo.tolerance 
              assignin("base","numericalInput",numericalInput)
              assignin("base","numericalData",numericalData)
              assignin("base","tol",attributeInfo.tolerance)
              obj.failCase(attribute,numericalInput,numericalData);            
          else
              updatedVal = numericalData/attributeInfo.conversionFactor;
          end
      end
      
      function [obj,foundState] = writeToggleProtocol(obj,setState,varargin)
          % Write on/off command to instrument
          %   Handles various forms of on/off input
          
          checkConnection(obj)
          
          if nargin == 3
             attributeInfo = varargin{1};
          end
           if ~exist('attributeInfo','var') || ~isfield(attributeInfo,'query')
             attributeInfo.query = obj.commands.('toggleQuery');
           end
           if ~isfield(attributeInfo,'toggleOn')
             attributeInfo.toggleOn = obj.commands.toggleOn;
           end
           if ~isfield(attributeInfo,'toggleOff')
             attributeInfo.toggleOff = obj.commands.toggleOff;
           end
           if ~isfield(attributeInfo,'toggleName')
              attributeInfo.toggleName = 'enabled';
           end
     
          setState = instrumentType.discernOnOff(setState);
          if strcmp(setState,'on')
             toggleCommand = attributeInfo.toggleOn;
          elseif strcmp(setState,'off')
             toggleCommand = attributeInfo.toggleOff;
          end
          
          %Reads data to check if current setting matches input given
          if (isfield(obj,'uncommonProperties') && isfield(obj.uncommonProperties.bypassPreCheck) && ~obj.uncommonProperties.bypassPreCheck)...
                  || strcmpi(setState,'query')
             [obj,toggleStatus] = readToggle(obj,attributeInfo.query);%Dependent on instrument
             foundState = instrumentType.discernOnOff(toggleStatus);

             if strcmp(setState,'query')
                return
             end

             if strcmp(setState,toggleStatus)
                className = class(obj);
                className(className=='_') = ' ';
                printOut(obj,sprintf('%s already %s',className,obj.status))
                return
             end
          end
          
          obj = writeToggle(obj,toggleCommand);

          %Bypass check after if enabled
          if obj.uncommonProperties.bypassPostCheck 
             foundState = instrumentType.discernOnOff(setState);
             return
          end
          
          [obj,toggleStatus] = readToggle(obj,attributeInfo.query);
          toggleStatus = instrumentType.discernOnOff(toggleStatus);
          
          if ~strcmp(toggleStatus,setState)
             className = class(obj);
             className(className=='_') = ' ';
             error('Attempted to turn %s %s, but it failed ',setState,className)
          else
             foundState = toggleStatus;
          end
          
      end
      
      function obj = loadConfig(obj,fileName,configFields,commandFields,numericalFields)
          % Load and validate instrument configuration from file
          %   Checks required fields and numerical parameters
          
          load(fileName,'config');
          
          %For each field of the loaded file, change the object's field to
          %match
          for ii = fieldnames(config)'
              if isa(obj.(ii{1}),'struct')
                  for jj = fieldnames(config.(ii{1}))'
                      obj.(ii{1}).(jj{1}) = config.(ii{1}).(jj{1});
                  end
              else
                  obj.(ii{1}) = config.(ii{1});
              end
          end
          
          %Check presence of required config fields
          if ~isempty(configFields)
          for ii = configFields
             if isempty(obj.(ii{1}))
                error('Invalid config file. Config must include %s',ii{1})
             end
          end
          end
          if ~isempty(commandFields)
              for ii = commandFields
                  if ~isfield(obj.commands,ii{1})
                      error('Invalid config file. Config commands must include %s',ii{1})
                  end
              end
          end
          %Numerical fields must have units, minimum, maximum, and
          %conversion factor
          %Conversion factor is the value numbers must be multiplied by when
          %going from the object's values to the instrument
          if ~isempty(numericalFields)
             neededInfo = {'units','conversionFactor','minimum','maximum'};
             for ii = numericalFields            
                for jj = neededInfo
                   if isempty(obj.(strcat(ii{1},'Info')).(jj{1}))
                      error('Invalid config file. Config must include %s %s',ii{1},jj{1})
                   end
                end
             end
          end
          
      end
      
      function [obj,outputInfo] = readInstrument(obj,varargin)
          % Read data from instrument
          %   Supports different connection types with error recovery
          
          try
              if isempty(obj.uncommonProperties.connectionType)
                  error('No connection type given (com, serialport')
              end

              %If there is a second argument given, send a write command to the instrument prior to reading
              if nargin > 1
                 queryCommand = varargin{1};
              end

              %Dependent on connection type and whether query command is given, send commands to instrument to obtain data
              switch lower(obj.uncommonProperties.connectionType)
                  case {'com','visadev'}
                    if nargin > 1
                       writeline(obj.handshake,queryCommand)
                    end
                    outputInfo = readline(obj.handshake);
                  case 'serialport'
                     if nargin > 1
                        fprintf(obj.handshake,queryCommand);
                     end
                     outputInfo = fscanf(obj.handshake);
              end
              
          catch readErr
              % Get current state for error logging
              currentState = struct(...
                  'connectionType', obj.uncommonProperties.connectionType, ...
                  'connected', obj.connected, ...
                  'handshake', class(obj.handshake));
              
              % Log the error
              obj.logError(obj,readErr, currentState);             
              
              rethrow(readErr);
          end
      end

      function obj = writeInstrument(obj,commandInput)
          % Write command to instrument
          %   Supports different connection types with error recovery
          
          try
              if isempty(obj.uncommonProperties.connectionType)
                  error('No connection type given (com, visadev, serialport)')
              end

              %Dependent on connection type, send command to instrument
              switch lower(obj.uncommonProperties.connectionType)
                  case {'com','visadev'}
                    writeline(obj.handshake,commandInput)               
                  case 'serialport'
                     fprintf(obj.handshake,commandInput);
              end
              
          catch writeErr
              % Get current state for error logging
              currentState = struct(...
                  'connectionType', obj.uncommonProperties.connectionType, ...
                  'connected', obj.connected, ...
                  'command', commandInput, ...
                  'handshake', class(obj.handshake));
              
              % Log the error
              obj.logError(obj,writeErr, currentState);
              
              
              rethrow(writeErr);
          end
      end

   end
   
   methods (Static)
      
      function onOff = discernOnOff(inputValue)
          % Convert various on/off inputs to standardized form
          
          switch lower(string(inputValue))
              case {'1','true','yes','y','on','t'}
                 onOff = 'on';
              case {'0','false','no','n','off','f'}
                 onOff = 'off';
              case {'q','query'}
                 onOff = 'query';
              case {'standby'}
                 onOff = 'standby';
             otherwise
                 tempInput = lower(char(inputValue));
                 switch tempInput(1)
                     case {'1','true','yes','y','on','t'}
                         onOff = 'on';
                     case {'0','false','no','n','off','f'}
                         onOff = 'off';
                     case {'q','query'}
                         onOff = 'query';
                     case {'standby'}
                         onOff = 'standby';
                     otherwise
                         error('Input must be on, off, or query (or a varaint such as true, false, or q). Input given: %s',inputValue)
                 end               
          end
      end
      
      function obj = overrideStruct(obj,s)
          % Override object fields with matching structure fields
          
          sfn = fieldnames(s);
          for ii = 1:numel(sfn)
             obj.(sfn{ii}) = s.(sfn{ii});
          end
          
          %Placed into static functions because this can be used for any two
          %structures         
      end

      function portNumber = checkPort
          % Identify instrument port through connect/disconnect sequence
          
          b = msgbox('Turn off/disconnect instrument','Turn off instrument');         
          while isvalid(b)
             pause(1)
          end
          
          numList = num2cell(serialportlist);
          numList = cellfun(@(a)convertStringsToChars(a),numList,'UniformOutput',false);
          numList = str2double(cellfun(@(a)a(4:end),numList,'UniformOutput',false));
          
          b = msgbox('Turn on/reconnect instrument','Turn on instrument');
          while isvalid(b)
             pause(1)
          end
          
          numList2 = num2cell(serialportlist);
          numList2 = cellfun(@(a)convertStringsToChars(a),numList2,'UniformOutput',false);
          numList2 = str2double(cellfun(@(a)a(4:end),numList2,'UniformOutput',false));
          
          portNumber = numList2(~ismember(numList2,numList));
          fprintf('Instrument port: %d\n',portNumber)
      end
      
      function s = addStructIndex(s,valuesToAdd,varargin)
          % Add or insert values into structure at specified index
          
          %Whether to insert or replace if address is specified. If no argument is given, defaults to insert
          if nargin > 3 
             switch lower(varargin{2})
                case {'insert','i','add'}
                   insertOrReplace = 'insert';
                case {'replace','r','swap'}
                   insertOrReplace = 'replace';
             end
          else
             insertOrReplace = 'insert';
          end

          %Index of where to add into the structure. Defaults to add onto the end
          if nargin > 2 
             indexToAdd = varargin{1};
             if ~isa(indexToAdd,'double'),   error('Index to add must be a double'),    end

             if strcmp(insertOrReplace,'replace')
                if indexToAdd > numel(s)
                   warnMessage = sprintf('Index greater than possible length, changed to %d',numel(s));
                   warndlg(warnMessage,'Over Maximum Index')
                end
             else
                if indexToAdd > numel(s)+1
                   warnMessage = sprintf('Index greater than possible length, changed to %d',numel(s)+1);
                   warndlg(warnMessage,'Over Maximum Index')
                end
             end

          else
             indexToAdd = numel(s)+1;
          end

          %Moves entire structure to insert new values
          if strcmp(insertOrReplace,'insert') && ~isempty(s) && indexToAdd <= numel(s)            
             s(indexToAdd+1:end+1) = s(indexToAdd:end);
          end

          if isempty(s)
              s = valuesToAdd;
          end

          %Adds new value
          s(indexToAdd) = valuesToAdd;         
      end

      function properIdentifier = giveProperIdentifier(userIdentifier)
          % Convert user-friendly names to standardized identifiers
          
          %Checks for multiple inputs and creates empty cell array
          userIdentifier = c2s(userIdentifier);
          properIdentifier = cell(1,numel(userIdentifier));

          for ii = 1:numel(userIdentifier)
             switch lower(userIdentifier(ii))
                case {'srs','srs_rf','srs rf','srsrf'}
                   properIdentifier{ii} = 'SRS RF';
                case {'wf','windfreak','wind freak','wind_freak','wf rf','wf_rf'}
                   properIdentifier{ii} = 'WF RF';
                case {'pulse_blaster','pulse blaster','pb','pulseblaster','spincore'}
                   properIdentifier{ii} = 'Pulse Blaster';
                case {'stage','pi','pistage','pi_stage','pi stage'}
                   properIdentifier{ii} = 'PI Stage';
                case {'daq','data','data acquisition','data_acquisition','dataacquisition','ni','ni daq','ni_daq','nidaq'}
                   properIdentifier{ii} = 'NI DAQ';
                case {'hamm','ham','hamamatsu','hammcam','hamcam','cam','camera'}
                   properIdentifier{ii} = 'Hamamatsu';
                case {'ddl','dynamic delay line','dynamicdelayline','dynamic_delay_line'}
                   properIdentifier{ii} = 'DDL';
                case {'ndyag','ndyov','532','532 nm','532nm','green laser','nv laser','laser532','laser 532','532 nm laser'}
                   properIdentifier{ii} = '532 nm Laser';
                otherwise
                   properIdentifier{ii} = [];
             end
          end

          %If only one input given, give it back in the form of a character array instead of cell
          if isscalar(properIdentifier)
             properIdentifier = properIdentifier{1};
          end
      end

      function logError(obj, errorInfo, currentState)
          % Log error with device state to file and memory
          
          % Create new error entry with timestamp
          newError = struct(...
              'timestamp', datetime('now'), ...
              'error', errorInfo);
          
          % Add to memory log with size limit
          if isempty(obj.errorLog)
              obj.errorLog = newError;
          else
              if length(obj.errorLog) >= obj.maxLogSize
                  obj.errorLog(1) = []; % Remove oldest entry
              end
              obj.errorLog(end+1) = newError;
          end
          
          % Write to log file with detailed state info
          try
              logFile = fopen(obj.logFileName, 'a');
              fprintf(logFile, '[%s] %s - Device: %s\n', ...
                  char(newError.timestamp), ...
                  newError.error.message, ...
                  obj.identifier);
              fprintf(logFile, 'State at error:\n');
              
              % Log each state field with appropriate formatting
              stateFields = fields(currentState);
              for ii = 1:numel(stateFields)
                  field = stateFields{ii};
                  value = currentState.(field);
                  if isnumeric(value)
                      fprintf(logFile, '  %s: %g\n', field, value);
                  elseif islogical(value)
                      fprintf(logFile, '  %s: %d\n', field, value);
                  elseif ischar(value) || isstring(value)
                      fprintf(logFile, '  %s: %s\n', field, value);
                  end
              end
              fprintf(logFile, '----------------------------------------\n');
              fclose(logFile);
          catch failedLog
              warning(failedLog.identifier, 'Failed to write to error log file: %s', failedLog.message);
          end
      end

   end
end