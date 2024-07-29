function NDYOVSetPower
%Changes Nd:YOV laser power

%Instrument dependencies:
%Nd:YOV laser

%Code dependencies:
%InitializationCheck
%NDYOVInitialization
%NDYOVEquilibrium

%NDYOVSetPower v2.0 4/20/22

global NDYOV %#ok<*GVMIS>
global master

%Check if Nd:YOV laser is initialized
InitializationCheck('NDYOV')

%Queries instrument as to set power
while true
   
    writeline(NDYOV,"POWER SET?")
    currentset = convertStringsToChars(readline(NDYOV));
    
    %If taking away 10 characters gives a number, stop loop
    try
        currentset(1:10) = [];
        currentset = str2double(currentset);
        break
    catch
        pause(.1)
    end
end

%Checks if on/off status has already been set. If not, asks for user input.
%Changes Nd:YOV laser power
while true
   
   if isfield(master.NDYOV, 'setpower')
      aa = master.NDYOV.setpower;
      
      if isscalar(aa) && ~isstring(aa)
         
         if aa >= .01 && aa <= 8
            
            if currentset ~= aa
               writeline(NDYOV,sprintf('POWER SET=%.2f',master.NDYOV.setpower))
               if master.notifications
                  fprintf('Nd:YOV power set to %.2f\n',master.NDYOV.setpower)
               end
            else
               if master.notifications
                  fprintf('Nd:YOV already set to %.2f\n',master.NDYOV.setpower)
               end
            end            
            break
            
         else
            
            if master.notifications
               fprintf('Nd:YOV set power must be between 0 and 8\n')
            end       
            
         end         
      else
         
         if master.notifications
            fprintf("Nd:YOV set power must be a scalar\n")
         end
         
      end      
   end
   
   master.NDYOV.setpower = input('Set power of Nd:YOV laser (Watts)?\n');
end

%Waits for equilibrium if waitforequilibrium is true
NDYOVEquilibrium

end

