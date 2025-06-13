classdef instrumentType < handle
   %instrumentType - Base class for all instrument types
   %
   % This class provides common functionality for all instrument types:
   %   - Connection management
   %   - Configuration loading
   %   - Parameter validation
   %   - Error handling
   %
   % Properties:
   %   connected - Connection status
   %   identifier - Instrument identifier
   %   presets - User-defined settings
   %   defaults - Default settings
   %
   % Methods:
   %   connect - Establish connection
   %   disconnect - Close connection
   %   loadConfig - Load configuration
   %   checkConnection - Validate connection
   %   discernOnOff - Convert on/off values
   %   setParameter - Set parameter value
   %   getParameter - Get parameter value

   properties      
      uncommonProperties %Structure containing properties that are uncommonly accessed and would clutter property list
      notifications = false
      presets
      %Below suppresses warnings from references to property that isn't
      %defined here. It is suppressed as not all functions are for all
      %instruments and there is therefore some lacking overlap
      %#ok<*MCNPN>
   end

   properties (SetAccess = protected, GetAccess = public)
   %Read-only for user (derived from config), stored in properties
   defaults
   connected = false
   identifier
   end

   methods
      function obj = instrumentType
         obj.uncommonProperties.connectionType = [];
         obj.uncommonProperties.bypassPreCheck = false; %Bypasses
         obj.uncommonProperties.bypassPostCheck = false;
      end
      
      function printOut(obj,printMessage)
         %Prints out a message if notifications are turned on. Incredibly
         %common so it is better to just have a function to make 3 lines
         %into 1
         if obj.notifications
             %Interestingly, I have to convert it to a string with the
             %ending \n otherwise all other \n in a message will not work
             fullMessage = sprintf('%s\n',printMessage);
            fprintf(fullMessage)
         end
      end


      function s = checkSettings(obj,propertyNames) %checkSetValue former name
         %Returns what the value for the given property name should be.
         %First check if there already is a value, then check if a preset
         %exists, then use the default if nothing else is present
         
         mustBeA(propertyNames,["char","string","cell"])         
         p = string(propertyNames);
         
         %For every property name, determine run through determination
         %process
         for ii = 1:numel(p)
            %Shorthand name to prevent needing parentheses
            m = p(ii);
            
            %Return the value it already has if it isn't empty
            if isprop(obj,m) && ~isempty(obj.(m))
               s.(m) = obj.(m);
               continue
            end
            
            %If there is a preset for this property, assign it the preset
            if isprop(obj,'presets') && isfield(obj.presets,m) && ~isempty(obj.presets.(m))
               s.(m) = obj.presets.(m);
               continue
            end
            
            %Use default value if nothing else is present. If there is no
            %default, return empty value and give warning
            if isprop(obj,'defaults') && isfield(obj.defaults,m) && ~isempty(obj.defaults.(m))
               s.(m) = obj.defaults.(m);
            else
               s.(m) = [];
               warning('%s property within %s checked for preset/default but neither was present',m,class(obj))
            end            
         end
         
         %If there is only 1 field name of the output (meaning only 1 input
         %name), return the variable directly rather than in a structure
         if isscalar(fieldnames(s))
            s = s.(m);
         end
      end
      
      function checkConnection(obj)
         %Checks connection of instrument. Incredibly common so it is
         %better to just have a function to make 3 lines into 1
         if isempty(obj.connected) || ~obj.connected
            error(['Connection must be established to instrument to execute this function. ' ...
                'Use the connect(object,configName) function to begin connection'])
         end
      end

      function shouldChange = changeNeeded(obj,setState,attribute,minimumAttribute,maximumAttribute)
         %Input is query, no change needed
         if ~isa(setState,'double')
            shouldChange = false;
            return
         end
         
         %Attribute already what the input is, no change needed
         if setState == obj.(attribute)
             printOut(obj,sprintf('%s already %g',attribute,obj.(attribute)))
            shouldChange = false;
            return
         end
         
         %Check attribute bounds then set new attribute if it is within
         %those bounds
         if obj.(minimumAttribute) < setState && setState <= obj.(maximumAttribute)
            shouldChange = true;
            return
         else
            error('%s input must be between %g and %g',...
               obj.(attribute),obj.(minimumAttribute),obj.(maximumAttribute))
         end
            
      end
      
      function [obj,updatedVal] = writeNumberProtocol(obj,attribute,setState,varargin)
         checkConnection(obj)
         if ~strcmp(setState,'query') && ~isa(setState,'double') 
            error('Write number input must be double or the string "query"')
         end
         
         %Gives option to input its own information, otherwise follows
         %standard naming convention to get relevant info
         if nargin > 3 && ~isempty(varargin{1})
            attributeInfo = varargin{1};
         end
         
         %Slightly different naming convention for each property of the
         %attribute to make readbility easier. Makes this bit a little more
         %complicated but ultimately not too bad
         %Check each relevant variable to see if it has been specified by
         %the optional input. If it hasn't use the default naming
         %conventions to obtain the value
         if ~exist('attributeInfo','var') || ~isfield(attributeInfo,'query')
            attributeInfo.query = obj.commands.(strcat(attribute,'Query')); 
         end
         attInfoStr = strcat(attribute,'Info');
         if ~isfield(attributeInfo,'conversionFactor')
            attributeInfo.conversionFactor = obj.(attInfoStr).('conversionFactor');%Multiply when writing, divide when reading
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
            if isfield(obj.(attribute),'tolerance') %Not everything has tolerance
               attributeInfo.tolerance = obj.attInfoStr.('tolerance');
            else
               attributeInfo.tolerance = abs(setState)*.00001;
            end        
         end

         %Reads data to check if current setting matches input given
         if ~obj.uncommonProperties.bypassPreCheck || strcmpi(setState,'query') 
            [obj,numericalData] = readNumber(obj,attributeInfo.query);%Dependent on instrument
            
            %This is remarkably stupid where the write units of the instrument
            %are not the same as the read units. Only the windfreak RF
            %generator does this, but it has to be corrected here otherwise
            %the readout is wrong
            if nargin > 4 && ~isempty(varargin{2})
               numericalData = numericalData * varargin{2};
            end
            updatedVal = numericalData./attributeInfo.conversionFactor;

            %If it is a query, only one reading is performed
            if strcmpi(setState,'query');     return;    end   

            %Attribute already what the input is, no change needed
            if setState <= updatedVal + attributeInfo.tolerance && setState >=updatedVal - attributeInfo.tolerance %#ok<BDSCI>
               printOut(obj,sprintf('%s already %g %s',attribute,updatedVal,attributeInfo.units))
               return
            end                     
         end         
         
         %Check attribute bounds then set new attribute if it is within those bounds
         if attributeInfo.minimum <= setState && setState <= attributeInfo.maximum
            numericalInput = setState*attributeInfo.conversionFactor;
            obj = writeNumber(obj,attribute,numericalInput);%Dependent on instrument
         else
            error('%s must be between %g and %g %s (%g given)',...
               attribute,attributeInfo.minimum,attributeInfo.maximum,attributeInfo.units,setState)
         end
         
         %If bypassing check after reading, set output to whatever input was given
         if obj.uncommonProperties.bypassPostCheck
            updatedVal = setState;
            return
         end
         
         [obj,numericalData] = readNumber(obj,attributeInfo.query);%Dependent on instrument

         %See previous note about unit mismatch
         if nargin > 4 && ~isempty(varargin{2})
             numericalData = numericalData * varargin{2};
         end
         
         %Checks if new reading matches input value
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
         %Load config file with variable "config"
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
         if isempty(obj.uncommonProperties.connectionType), error('No connection type given (com, serialport'); end

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
      end

      function obj = writeInstrument(obj,commandInput)
         if isempty(obj.uncommonProperties.connectionType), error('No connection type given (com, visadev, serialport)'); end

         %Dependent on connection type, send command to instrument
         switch lower(obj.uncommonProperties.connectionType)
             case {'com','visadev'}
               writeline(obj.handshake,commandInput)               
            case 'serialport'
               fprintf(obj.handshake,commandInput);
         end
      end

   end
   
   methods (Static)
      
      function onOff = discernOnOff(inputValue)
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
         %Replaces all fields in obj with the values for those fields in s so
         %long as those fields exist in s     
         sfn = fieldnames(s);
         for ii = 1:numel(sfn)
            obj.(sfn{ii}) = s.(sfn{ii});
         end
         
         %Placed into static functions because this can be used for any two
         %structures         
      end

      function portNumber = checkPort
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
         %Adds new values to structure
         
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
         %Gives identifier based on input name of instrument

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

   end
end