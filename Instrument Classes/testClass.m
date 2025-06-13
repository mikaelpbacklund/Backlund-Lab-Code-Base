classdef testClass < instrumentType
   %testClass - A test class for instrument control
   %
   % Features:
   %   - Basic instrument control
   %   - Status monitoring
   %   - Parameter management
   %
   % Usage:
   %   tc = testClass('configFileName.json');
   %   tc.connect();
   %   tc.setParameter('value', 1);
   %   val = tc.getParameter('value');
   %
   % Dependencies:
   %   - JSON configuration file with test settings

   properties (Dependent)
      % Properties that can be modified by the user
      value            % Test value
      status          % Current status
   end

   properties (SetAccess = {?testClass ?instrumentType}, GetAccess = public)
      % Properties managed internally by the class
      manufacturer    % Test manufacturer
      model          % Test model
      handshake      % Test connection handle
   end

   methods
      function obj = testClass(configFileName)
         %testClass Creates a new test instance
         %
         %   obj = testClass(configFileName) creates a new test instance
         %   using the specified configuration file.
         %
         %   Throws:
         %       error - If configFileName is not provided
         
         if nargin < 1
            error('testClass:MissingConfig', 'Config file name required as input')
         end

         %Loads config file and checks relevant field names
         configFields = {'manufacturer','model'};
         commandFields = {};
         numericalFields = {};
         obj = loadConfig(obj,configFileName,configFields,commandFields,numericalFields);
      end
      
      function obj = connect(obj)
         %connect Establishes connection with the test device
         %
         %   obj = connect(obj) connects to the test device and initializes
         %   settings.
         %
         %   Throws:
         %       error - If test device is already connected
         
         if obj.connected
            error('testClass:AlreadyConnected', 'Test device is already connected')
         end

         %Create test connection
         obj.handshake = serialport(obj.manufacturer, 9600);
         configureTerminator(obj.handshake, "CR/LF");
         
         obj.connected = true;
         obj.identifier = 'TestDevice';
         
         %Set default values
         obj = setParameter(obj, 0, 'value');
      end
      
      function obj = disconnect(obj)
         %disconnect Disconnects from the test device
         %
         %   obj = disconnect(obj) disconnects from the test device and
         %   cleans up resources.
         
         if ~obj.connected
            return;
         end
         
         if ~isempty(obj.handshake)
            obj.handshake = [];
         end
         
         obj.connected = false;
      end
      
      function obj = setParameter(obj, value, parameter)
         %setParameter Sets a parameter value
         %
         %   obj = setParameter(obj,value,parameter) sets the specified
         %   parameter to the given value.
         %
         %   Throws:
         %       error - If test device is not connected
         
         checkConnection(obj)
         
         %Send parameter command to test device
         writeline(obj.handshake, sprintf('%s %d', parameter, value))
         obj.(parameter) = value;
      end
      
      function value = getParameter(obj, parameter)
         %getParameter Gets a parameter value
         %
         %   value = getParameter(obj,parameter) returns the value of the
         %   specified parameter.
         %
         %   Throws:
         %       error - If test device is not connected
         
         checkConnection(obj)
         
         %Query parameter from test device
         writeline(obj.handshake, sprintf('%s?', parameter))
         value = str2double(readline(obj.handshake));
      end
   end

   methods
      function set.value(obj, val)
         obj = setParameter(obj, val, 'value');
      end
      function val = get.value(obj)
         val = getParameter(obj, 'value');
      end

      function set.status(obj, val)
         obj = setParameter(obj, val, 'status');
      end
      function val = get.status(obj)
         val = getParameter(obj, 'status');
      end
   end
end