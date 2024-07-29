function NDYOVEquilibrium
%If .waitforequilibrium is true, waits for laser equilibrium

%Instrument dependencies:
%Nd:YOV laser

%Code dependencies:
%InitializationCheck
%NDYOVInitialization

%NDYOVEquilibrium v1.0 4/20/22

global NDYOV %#ok<*GVMIS>
global master

%Check if Nd:YOV laser is initialized
InitializationCheck('NDYOV')

%If waitforequilibrium is false, immediately end function
if master.NDYOV.waitforequilibrium
   
   firstwait = true; 
   while true
      
      %If laser is off, immediately end function
      if master.NDYOV.switch ==  "off"
         break
      end
      
      %If this is the first loop, print waiting message
      if firstwait
         fprintf('Waiting for laser equilibrium')
         firstwait = false;
      end
      
      %Queries current actual power
      while true
         
         writeline(NDYOV,'POWER?');
         master.NDYOV.power = convertStringsToChars(readline(NDYOV));
         
         %If taking away 6 characters gives a number, stop loop
         try
            master.NDYOV.power(1:6) = [];
            master.NDYOV.power = str2double(master.NDYOV.power);
            break
         catch
            fprintf('.')
            pause(.5)
         end
         
      end
      
      %If actual power is within tolerance of set power, end loop;
      %otherwise, repeat
      aa = master.NDYOV.power <= master.NDYOV.setpower + master.NDYOV.tolerance;
      bb = master.NDYOV.power >= master.NDYOV.setpower - master.NDYOV.tolerance;
      if aa && bb
         fprintf('\nLaser equilibrated\n')
         break
      else
         fprintf('.')
         pause(.5)
      end
      
   end
   
end

end









