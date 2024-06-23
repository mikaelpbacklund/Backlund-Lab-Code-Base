function RFInitialization
%Initializes SRS RF generator. Can use pre-input parameters or request user
%input directly.

%Instrument dependencies:
%SRS RF generator

%Code dependencies:
%InitializationCheck
%RFFrequency*
%RFAmplitude*
%RFSwitch*

%* indicates only required if corresponding setting is already present

%RFInitialization v2.0 4/19/22

global RF %#ok<*GVMIS>
global master

if ~isfield(master,'notifications'),    master.notifications = true;     end

%Checks if master.RF.initialized exists in usable form. If not,
%makes said variable false
iscorrect = false;
if isfield(master,'RF')
    if isfield(master.RF,'initialized')
        if master.RF.initialized
            iscorrect = true;
        end
    end
end
if ~iscorrect
    master.RF.initialized = false;
end

%Begins initialization if not already initialized
if ~master.RF.initialized

    %Attempts to connect to RF generator via NI GPIB
    try
        RF=gpib('ni',0,27);
        fopen(RF);
    catch ME
       try
        fclose(RF);
        delete(RF)
        clear global RF
       catch
       end
        if master.notifications
            fprintf('Error connecting to RF generator\n')
        end
        rethrow (ME)
    end

    %Sets initialization status to true then inputs frequency, amplitude,
    %and on/off switch
    master.RF.initialized = true;

    %If value is already set, change corresponding setting, otherwise
    %remain at current value and update the setting
    if isfield(master.RF,'switch')
       RFSwitch
    else
       fprintf(RF,'ENBR?');
       status = fscanf(RF);
       if strcmp(status(1),'0')
          master.RF.switch = "off";
       else
          master.RF.switch = "on";
       end
    end
    
    if isfield(master.RF,'frequency')
       RFFrequency
    else
       fprintf(RF,'FREQ? MHz');
       master.RF.frequency = str2double(fscanf(RF))/1000;
    end
    
    if isfield(master.RF,'amplitude')
       RFAmplitude
    else
       fprintf(RF,'AMPR?');
       master.RF.amplitude = str2double(fscanf(RF));
    end

    if ~isfield(master.RF,'modulationType')
       master.RF.modulationType = 'I/Q';
    end
    
    if isfield(master.RF,'modwave') && isfield(master.RF,'modulationOn')
       RFModulation
    else
       
       if ~isfield(master.RF,'modwave')
          fprintf(RF,'MFNC?');
          switch fscanf(RF)
             case '0'
                master.RF.modwave = "sine";
             case '1'
                master.RF.modwave = "ramp";
             case '2'
                master.RF.modwave = "triangle";
             case '3'
                master.RF.modwave = "square";
             case '4'
                master.RF.modwave = "noise";
             case '5'
                master.RF.modwave = "external";
          end
       end
       
       if ~isfield(master.RF,'modulationOn')
          fprintf(RF,'MODL 0');
          master.RF.modulationOn = false;
       else
            if master.RF.modulationOn
                fprintf(RF,'MODL 1');
            else
                fprintf(RF,'MODL 0');
            end
       end
       RFModulation
    end
    
    if master.notifications
        fprintf("RF generator successfully initialized\n")
    end

else
    if master.notifications
        fprintf("RF generator already initialized\n")
    end
end

end
