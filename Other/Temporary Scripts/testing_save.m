targetFolder = 'Saved Data';

% 1. Determine where "Saved Data" is located
if isfolder(targetFolder)
    % You are currently in the root folder
    destinationDir = fullfile(pwd, targetFolder);
else
    % You are in a child folder, so check one level up (the parent)
    parentDir = fileparts(pwd); 
    destinationDir = fullfile(parentDir, targetFolder);
end