function NDYOVSwitch
%Turns Nd:YOV laser on/off

%Instrument dependencies:
%Nd:YOV laser

%Code dependencies:
%InitializationCheck
%NDYOVInitialization
%NDYOVEquilibrium

%NDYOVSwitch v2.0 4/20/22

global NDYOV %#ok<*GVMIS>
global master

%Check if Nd:YOV laser is initialized
InitializationCheck('NDYOV')

while true
   
   %Queries laser as to on/off status
   writeline(NDYOV,"OPMODE?")
   currentstatus = convertStringsToChars(readline(NDYOV));
   
   %If taking away 7 characters gives a valid status, continue
   try
      currentstatus(1:7)=[];
   catch
      currentstatus = "failed";
   end
   
   %When currentstatus is a viable option, changes format to match
   %that of master, otherwise waits half a second for laser to
   %respond
   switch currentstatus
      case 'OFF'
         currentstatus = "off";
         break
      case 'ON'
         currentstatus = "on";
         break
      case 'IDLE'
         currentstatus = "idle";
         break
      otherwise
         pause(.1)
   end
   
end

%Checks if on/off status has already been set. If not, asks for user input.
%Turns Nd:YOV laser on or off.
while true
   
   if isstring(master.NDYOV.switch)
      
      %If current status is the same as set status
      if currentstatus == master.NDYOV.switch
         
         if master.notifications
            fprintf('Nd:YOV already %s\n',master.NDYOV.switch)
         end
         break
         
      else
         
         %If current status is different from set status, send set status
         %as command to laser if set status is valid
         switch master.NDYOV.switch
            
            case 'on'
               writeline(NDYOV,"OPMODE=ON")
               if master.notifications
                  fprintf('Nd:YOV switched on\n')
               end
               break
               
            case 'off'
               writeline(NDYOV,"OPMODE=OFF")
               if master.notifications
                  fprintf('Nd:YOV switched off\n')
               end
               break
               
            case 'idle'
               writeline(NDYOV,"OPMODE=IDLE")
               if master.notifications
                  fprintf('Nd:YOV switched to idle\n')
               end
               break
               
            otherwise %Set status is invalid
               if master.notifications
                  fprintf('Nd:YOV switch must be "on", "off", or "idle"\n')
               end
         end

      end
      
   else
      
      if master.notifications
         fprintf("Nd:YOV switch must be a string\n")
      end
      
   end
   
   master.NDYOV.switch = input('Switch Nd:YOV laser? "on" "off" "idle"\n');
   
end

%Waits for equilibrium if waitforequilibrium is true
NDYOVEquilibrium

end

