classdef laser < instrumentType
   
   properties
      wavelength %Laser wavelength, used primarily for display
      pauseTime
      waitForEquilibrium %Boolean for whether to wait until actual power matches set power
      offWhenDeleted %Should laser be turned off when object is deleted
      commands %Commands that can be sent to handshake
      handshake %Actual connection to instrument
      setPowerInfo %Contains information on how to change set power
      actualPowerInfo %Contains information on how to interpret actual power
      setPower %Current power setting      
      enabled %On/Off setting
   end

   properties (SetAccess = {?laser ?instrumentType}, GetAccess = public)
      actualPower %Current power reading. UPDATES FROM INSTRUMENT EVERY TIME ACCESSED
   end
   
   methods
      function obj = laser(configFileName)
         if nargin < 1
              error('Config file name required as input')
         end

         configFields = {'identifier','wavelength','uncommonProperties','pauseTime','waitForEquilibrium','offWhenDeleted'};
         commandFields = {'toggleOn','toggleOff','toggleQuery','setPowerQuery','setPower','actualPowerQuery'};
         numericalFields = {'setPower'};%has units, conversion factor, and min/max
         obj = loadConfig(obj,configFileName,configFields,commandFields,numericalFields);

         %Checks to make sure nested fields contain appropriate info
         mustContainField(obj.uncommonProperties,{'replyInfo','connectionType','tolerance','equilibrationTimeout'})
         if strcmpi(obj.uncommonProperties.connectionType,'com')
            mustContainField(obj.uncommonProperties,{'portNumber','baudRate'})
         end
         mustContainField(obj.uncommonProperties.replyInfo,{'numberOfReplies','realReplyLocation','discardAfterWrite',...
            'discardFirstConnectedResponse','charsDiscarded'})
         mustContainField(obj.uncommonProperties.replyInfo.charsDiscarded,{'actualPower','setPower','toggle'})
      end

      function delete(obj)
         if obj.offWhenDeleted
            obj.enabled = false;
         end
      end
      
      %% Internal Functions

      function [obj,numericalData] = readNumber(obj,attributeQuery)
         switch attributeQuery
             case obj.commands.setPowerQuery
                 varName = 'setPower';
             case obj.commands.actualPowerQuery
                 varName = 'actualPower';
         end
         [obj,numericalData] = queryInterpretation(obj,attributeQuery,obj.uncommonProperties.replyInfo.charsDiscarded.(varName));
         numericalData = str2double(numericalData);
      end
      
      function obj = writeNumber(obj,attribute,numericalInput)
         inputCommand = sprintf(obj.commands.(attribute),numericalInput);
         obj = writeInstrument(obj,inputCommand);
         if obj.uncommonProperties.replyInfo.discardAfterWrite
            [~] = readline(obj.handshake);%OK reply to every command
         end
         
      end
      
      function [obj,toggleStatus] = readToggle(obj,attributeQuery)  
         [obj,toggleStatus] = queryInterpretation(obj,attributeQuery,obj.uncommonProperties.replyInfo.charsDiscarded.toggle);
      end
      
      function obj = writeToggle(obj,toggleCommand)
         writeline(obj.handshake,toggleCommand)
         [~] = readline(obj.handshake);%OK reply to every command
      end
                  
      function [obj,queryOutput] = queryInterpretation(obj,attributeQuery,numberCharsDiscarded)
         %Requests reply from handshake repeatedly and selects "correct" reply with desired information
         %numberOfReplies, realReplyLocation, and numberCharsDiscarded must be found individually for each laser

         for ii = 1:obj.uncommonProperties.replyInfo.numberOfReplies
             if ii == 1
                 [obj,currentOutput] = readInstrument(obj,attributeQuery);
             else
                 [obj,currentOutput] = readInstrument(obj);
             end
             if ii == obj.uncommonProperties.replyInfo.realReplyLocation
                 queryOutput = s2c(currentOutput);
             end
         end

         %Discards however many characters set by input
         queryOutput = queryOutput(numberCharsDiscarded+1:end);
      end
      
      %% User functions      
      
      function obj = connect(obj)
         %visadevlist

         if strcmpi(obj.uncommonProperties.connectionType,'com')
            obj.handshake = serialport(sprintf('COM%d',obj.uncommonProperties.portNumber),obj.uncommonProperties.baudRate);
            configureTerminator(obj.handshake,"CR")
         end       
         
         if obj.uncommonProperties.replyInfo.discardFirstConnectedResponse
            %Query identification because first query gives different result from
            %later ones. Also a check on if the connection worked
            writeline(obj.handshake,"*IDN?")
            [~] = queryInterpretation(obj,0);
         end

         obj.connected = true;

         obj = queryToggle(obj);
         obj = querySetPower(obj);
         obj = queryActualPower(obj);
         obj = equilibrium(obj);         
      end
     
       function obj = equilibrium(obj,varargin)
         %Variable argument 1 is forcing pause time
         %Variable argument 2 is giving set power to reference instead of referencing property
         checkConnection(obj)
         
         %Waits for set amount of time if required
         if nargin > 1 && ~isempty(varargin{1}) && varargin{1}
            pause(obj.pauseTime)
         end

         %Uses input as reference power instead of property when using the set.setPower function
         if nargin > 2 && ~isempty(varargin{2})
            referencePower = varargin{2};
         else
            referencePower = obj.setPower;
         end

         %Don't check for equilibrium if set not to, just check the power
         if ~obj.waitForEquilibrium
            return
         end
         
         n = 1; %Counter for amount of times power is checked
         printOut(obj,'Waiting for laser equilibrium')
         t = datetime;
         
         while true %repeats until equilibrated

            %Queries actual power and stores as "currentPower"
            obj = queryActualPower(obj);
            
            %Within tolerance on both sides
            if  obj.actualPower <= referencePower + obj.uncommonProperties.tolerance &&  obj.actualPower >= referencePower - obj.uncommonProperties.tolerance
               printOut(obj,'\nLaser equilibrated')
               break
            else
               
               if mod(n,2) == 0 %prints "." every half second
                   if mod(n,12) == 0
                       printOut(obj,'.')
                   elseif obj.notifications
                       fprintf('.')
                   end
                  
               end
               n = n+1;
               
               if n > obj.uncommonProperties.equilibrationTimeout*4 %Laser shouldn't take more than 15 seconds to equilibrate
                   if obj.notifications
                       fprintf('\nEquilibrium not established (check tolerance setting). Set power: %.2f, actual power: %.2f Continuing...\n',...
                        obj.setPower,obj.actualPower)
                   end
                  return
               end
               
               c = datetime;
               pause(.25-seconds(c-t))
               t = datetime;
            end
         end
       end

       function obj = queryToggle(obj)
           [obj,foundState] = writeToggleProtocol(obj,'query'); 
           obj.enabled = foundState;
       end

       function obj = querySetPower(obj)
           [obj,foundState] = writeNumberProtocol(obj,'setPower','query');
            obj.setPower = foundState;
       end

       function obj = queryActualPower(obj)
         [obj,foundState] = writeNumberProtocol(obj,'actualPower','query');
         obj.actualPower = foundState;
       end

       %% Set/Get functions
      function set.setPower(obj,val)
         %Writes number to laser then runs equilibrium
         [obj,newVal] = writeNumberProtocol(obj,'setPower',val);
         if isempty(obj.setPower) || obj.setPower ~= newVal
             obj = queryActualPower(obj);
             obj.setPower = newVal;
             obj = equilibrium(obj,true);             
         end
      end

      function set.enabled(obj,val)
         [obj,foundState] = writeToggleProtocol(obj,val);          
         obj = equilibrium(obj,true);
         obj.enabled = foundState;
      end
   end    
      
   
end