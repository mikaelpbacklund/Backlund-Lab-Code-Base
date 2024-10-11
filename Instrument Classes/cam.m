classdef cam < instrumentType
   
   properties
      camera
      source
      bounds %rows, columns (not x,y)
      outputFullImage = true;
      outputFrameStack = true;
   end

   properties (Dependent)
      %Stored in camera/source object
      exposureTime
      defectCorrectionEnabled
      defectCorrectionLevel
      framesPerTrigger
   end

   properties (SetAccess = protected, GetAccess = public)
      %Read-only for user (derived from config)
      manufacturer
      imageType
   end

   methods

      function h = cam(configFileName)
         %Creates cam object

         if nargin < 1
            error('Config file name required as input')
         end

         %Loads config file and checks relevant field names
         configFields = {'manufacturer','imageType','defaults'};
         commandFields = {};
         numericalFields = {};
         h = loadConfig(h,configFileName,configFields,commandFields,numericalFields);

         %Set identifier as given name
         h.identifier = configFileName;
      end
      
      function delete(h)
      %What happens when the object is deleted
      %Turn off camera if possible before clearing object
         if ~isempty(h.camera)
            try
            stop(h.camera)
            catch
            end
         end
      end

      function h = connect(h)
         try
         %Creates the connection to the camera and its source
         h.camera = videoinput(h.manufacturer,1,h.imageType);
         h.source = getselectedsource(h.camera);
         h.connected = true;

         %Overrides only the values that aren't already set with either
         %their preset or default value
         h = instrumentType.overrideStruct(h,checkSettings(h,fieldnames(h.presets)));
         
         %Sets logging to RAM allocated to MatLab rather than saving to
         %disk which takes longer and makes a file
         h.camera.LoggingMode = 'memory';
         
         %When triggered, immediately takes frames
         triggerconfig(h.camera, 'immediate');
         
         %Sets the camera to an active state, ready to be triggered
         start(h.camera)
         
         printOut(h,'Camera Connected')
         catch
            h.connected = false;
         end
      end
      
      function [averageImages,frameStacks] = takeImage(h)
         checkConnection(h)
         
         %This block of code is used to prevent the camera from ever
         %getting a frame value above 100 (which would cause an error). I
         %am dividing the total frames into sets of 100 and an additional
         %last set of whatever the leftover value is
         storedFPT = h.camera.FramesPerTrigger;
         nsets = ceil(h.camera.FramesPerTrigger /100);
         lastset = mod(h.camera.FramesPerTrigger,100);
         h.framesPerTrigger = 100;
         
         for kk = 1:nsets
            %If this is the last set, change the frames per trigger to be
            %whatever the leftover value is
            if kk == nsets
               h.camera.FramesPerTrigger = lastset;
            end
            
            %Tells camera to take frames
            trigger(h.camera)
            
            %Obtains data from camera
            totalImageOut = getdata(h.camera);
            
            %Converts to 3D array. Unsure why a 4th is created in the first place
            totalImageOut = double(squeeze(totalImageOut));

            %Preallocation for full frame stack after getting image size
            if kk == 1
               totalFrames = zeros(size(totalImageOut,1),size(totalImageOut,1),storedFPT);
            end
            
            %Assigns image to the correct spot
            totalFrames(:,:,1+100*(kk-1):100*kk) = totalImageOut;
            
         end

         %Get number of expected output images
         nOutputs = getNumberOfImageOutputs(h,size(totalFrames(:,:,1)));
         
         %For each set of bounds, take the overall frame stack and cut it
         %down to the correct bounds. Then take the average of that cut
         %image to output
         for ii = 1:numel(h.useBounds)
            cutFrameStack = totalFrames(h.bounds{ii,1}(1):h.bounds{ii,1}(2),h.bounds{ii,2}(1):h.bounds{ii,2}(2),:);
            averageImages{ii} = mean(cutFrameStack,3); %#ok<AGROW>
            if h.outputFrameStack
               frameStacks{ii} = cutFrameStack; %#ok<AGROW>               
            end        
         end

         %If number of outputs and number of bounds are not the same, an additional set of images will be added that is
         %for the entire image
         if numel(h.useBounds) ~= nOutputs
            averageImages{end+1} = mean(totalFrames,3);
            if h.outputFrameStack
               frameStacks{end+1} = totalFrames;
            end
         end

         %Adds empty output for frameStacks if outputFrameStack is off
         if ~h.outputFrameStack
            frameStacks = [];
         end
         
         %Sets frames back to original
         h.framesPerTrigger = storedFPT;
         
      end
      
      function h = boundSelector(h)
         checkConnection(h)
         
         %Saves previous camera settings
         oldFramesPerTrigger = h.camera.FramesPerTrigger;
         h.camera.FramesPerTrigger = 1;
         oldFullImage = h.outputFullImage;
         h.outputFullImage = true;

         %Deletes previous bounds
         h.bounds = {};
         
         %Takes image that will be used to select the bounds
         totalIm = takeImage(h);
         
         %Resets camera settings back to what they were originally
         h.camera.FramesPerTrigger = oldFramesPerTrigger;
         h.outputFullImage = oldFullImage;
         
         %Two while loops. External loop is for selecting different sets of
         %bounds. Internal loop is for ensuring the bounds selected are
         %correct
         moreBounds = true;
         n = 1;
         while moreBounds
            
            correctBounds = false;
            while ~correctBounds
               %Creates figure with image that was taken
               figure('Name','Bounds Selector','NumberTitle','off');
               imagesc(totalIm);
               colormap(gray)
               
               %User selects a region within the image and the vertices of
               %that region are used to get the row/column bounds
               title('Please draw a rectangle around the desired area')
               roi = drawrectangle;
               rowBound = [round(roi.Vertices(1,2)) round(roi.Vertices(2,2))];
               colBound = [round(roi.Vertices(1,1)) round(roi.Vertices(3,1))];
               close('Bounds Selector')
               
               %Creates an image with the new bounds for confirmation
               figure('Name','Bounds Confirmation','NumberTitle','off');
               imagesc(totalIm(rowBound(1):rowBound(2),colBound(1):colBound(2)))
               colormap(gray)
               
               %If bounds are correct, break out of loop, otherwise restart
               %process
               correctBounds = strcmp(questdlg('Are these bounds correct?', 'Yes', 'No'),'Yes');
               close('Bounds Confirmation')
            end
            
            %Saves the selected bounds to the cam object
            %nx2 cell array where first column is for row bounds and second
            %is for column bounds
            h.bounds{n,1} = rowBound;
            h.bounds{n,2} = colBound;
            
            %If more bounds are desired, restart process and increment
            %counting variable
            boundsMessage = sprintf('Do you want to select another set of bounds? Current total is %d',n);
            moreBounds = strcmp(questdlg(boundsMessage,'Yes', 'No'),'Yes');
            n = n+1;
         end
      end
      
      function blankOutput = generateBlankOutput(h,varargin)
         %Creates a blank output based on the current bounds and settings
         %2nd argument is the full image size

         blankOutput = {};

         %For each set of bounds, find the x and y range then make a matrix
         %of zeros according to that size
         for ii = 1:numel(h.bounds)
            xRange = 1 + ex.hamm.bounds{ii,2}(2) - ex.hamm.bounds{ii,2}(1);
            yRange = 1+ ex.hamm.bounds{ii,1}(2) - ex.hamm.bounds{ii,1}(1);
            blankOutput{end+1} = zeros(yRange,xRange); %#ok<AGROW>
         end

         %Adds another matrix the size of the full image if it is enabled
         if h.outputFullImage            
            if nargin == 1
               error('Full image size (2nd argument) must be included if outputFullImage is enabled')
            end
            fullImageSize = varargin{1};
            blankOutput{end+1} = zeros(fullImageSize(1),fullImageSize(2));
         end

         %Repeat for frame stack if enabled
         if h.outputFrameStack
            for ii = 1:numel(h.bounds)
               xRange = ex.hamm.bounds{ii,2}(2) - ex.hamm.bounds{ii,2}(1);
               yRange = ex.hamm.bounds{ii,1}(2) - ex.hamm.bounds{ii,1}(1);
               blankOutput{end+1} = zeros(yRange,xRange,h.framesPerTrigger); %#ok<AGROW>
            end
            if h.outputFullImage
               blankOutput{end+1} = zeros(fullImageSize(1),fullImageSize(2),h.framesPerTrigger);
            end
         end

      end

      function nOutputs = getNumberOfImageOutputs(h,totalSize)
         %Find number of outputs that will be present based on number of bounds and whether those bounds match the full
         %image

         nOutputs = size(h.bounds,1);

         %If outputFullImage is off, number of outputs will just be number of bounds
         if ~h.outputFullImage
            return
         end

         %Checks each set of bounds to see if it matches the total size
         hasMaxSizeBounds  = false;
         for ii = 1:nOutputs
            if [h.bounds{ii,1}(1),h.bounds{ii,1}(2);h.bounds{ii,2}(1),h.bounds{ii,2}(2)] == [1,size(totalSize,1);1,size(totalSize,2)]
               hasMaxSizeBounds  = true;
            end
         end

         %If nothing matches the max size bounds (and outputFullImage is true), add 1 output
         if ~hasMaxSizeBounds
            nOutputs = nOutputs + 1;
         end
      end

   end

   %% Dependent Property Functions
   methods 
      %These functions make sure that there are no desyncing errors.

      %I normally create a property for each value that can be changed.
      %However, since e.g. "exposureTime" is set within the "source"
      %property, I cannot just make another variable for exposureTime
      %because it will not be the same as the real value within source.
      %Thus, I make exposureTime dependent on the value within source,
      %circumnavigating this issue
      function h = setParameter(h,val,varName,internalName)         
         if h.connected
            h.source.(internalName) = val;
         else
            h.presets.(varName) = val;
         end
      end
      function val = getParameter(h,varName,internalName)
         if h.connected
            val = h.source.(internalName);
         elseif isfield(h.presets,varName) && ~isempty(h.presets.(varName))
            val = h.presets.(varName);
         elseif isfield(h.defaults,varName) && ~isempty(h.defaults.(varName))
            val = h.defaults.(varName);
         else
            val  =[];
         end
      end      

      function set.exposureTime(h,val)
         h = setParameter(h,val,'exposureTime','ExposureTime'); %#ok<NASGU>
      end
      function val = get.exposureTime(h)
         val = setParameter(h,'exposureTime','ExposureTime');
      end

      function set.defectCorrectionEnabled(h,val)
         h = setParameter(h,val,'defectCorrectionEnabled','DefectCorrect'); %#ok<NASGU>
      end
      function val = get.defectCorrectionEnabled(h)
         val = setParameter(h,'defectCorrectionEnabled','DefectCorrect');
      end

      function set.defectCorrectionLevel(h,val)
         h = setParameter(h,val,'defectCorrectionLevel','HotPixelCorrectionLevel'); %#ok<NASGU>
      end
      function val = get.defectCorrectionLevel(h)
         val = setParameter(h,'defectCorrectionLevel','HotPixelCorrectionLevel');
      end

      %FramesPerTrigger is in camera not in source
      function set.framesPerTrigger(h,val)
         if h.connected
            h.camera.FramesPerTrigger = val;
         else
            h.presets.framesPerTrigger = val;
         end
      end
      function val = get.framesPerTrigger(h)
         varName = 'framesPerTrigger';
         if h.connected
            val = h.camera.FramesPerTrigger;
         elseif isfield(h.presets,varName) && ~isempty(h.presets.(varName))
            val = h.presets.(varName);
         elseif isfield(h.defaults,varName) && ~isempty(h.defaults.(varName))
            val = h.defaults.(varName);
         else 
            val = [];
         end
      end

   end

end