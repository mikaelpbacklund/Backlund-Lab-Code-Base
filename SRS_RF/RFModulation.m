function RFModulation
%Changes RF amplitude modulation wave type and turns it on/off

%Instrument dependencies:
%SRS RF generator

%Code dependencies:
%InitializationCheck
%RFInitialization

%RFAmplitudeModulation v2.0 4/19/22

global RF %#ok<*GVMIS>
global master

%Checks if RF generator has been initialized
InitializationCheck('RF')

if master.RF.modulationOn
   
   fprintf(RF, 'MODL 1');
   switch master.RF.modulationType
      case 'I/Q'
         fprintf(RF, 'TYPE 6');
         master.RF.modwave = "external";
         fprintf(RF, 'QFNC 5');
         if master.notifications
            fprintf('I/Q modulation on\n')
         end
      case 'Amplitude'
         
         fprintf(RF, 'TYPE 0');
         
         if master.notifications
            fprintf('Amplitude modulation on\n')
         end
         
         %Queries instrument as to modulation wave type
         fprintf(RF, 'MFNC?');
         switch fscanf(RF)
            case '0'
               currwave = "sine";
            case '1'
               currwave = "ramp";
            case '2'
               currwave = "triangle";
            case '3'
               currwave = "square";
            case '4'
               currwave = "noise";
            case '5'
               currwave = "external";
         end
         setwave = master.RF.modwave;
         
         %Compares current status to setting then sends wave type command to RF
         %generator followed by printing status a message
         if strcmp(currwave,setwave)
            fprintf('AM wave type already %s\n',setwave)
         else
            dontprint = false;
            switch setwave
               case 'sine'
                  fprintf(RF, 'MFNC 0');
               case 'ramp'
                  fprintf(RF, 'MFNC 1');
               case 'triangle'
                  fprintf(RF, 'MFNC 2');
               case 'square'
                  fprintf(RF, 'MFNC 3');
               case 'noise'
                  fprintf(RF, 'MFNC 4');
               case 'external'
                  fprintf(RF, 'MFNC 5');
               otherwise
                  fprintf('AM wave type must be "sine", "ramp", "triangle", "square", "noise", or "external". Wave type not changed\n')
                  dontprint = true;
            end
            
            if ~dontprint
               if master.notifications
                  fprintf('RF amplitude modulation wave type changed to a %s wave\n',setwave)
               end
            end
         end
         
   end
else
   fprintf(RF, 'MODL 0');
   if master.notifications
      fprintf('Modulation off\n')
   end
end

end


