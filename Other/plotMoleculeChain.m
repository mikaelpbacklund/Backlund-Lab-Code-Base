close all
% load("Coords_log.mat")
nTimesteps =10;
nChains = 136;
nCarbons = 100;
pauseTimePerTimestep = 3;

xAll = squeeze(mdData(1:nTimesteps,1:nChains,1:nCarbons,1));  % All x positions [timestep × chain × carbon]
yAll = squeeze(mdData(1:nTimesteps,1:nChains,1:nCarbons,2));
zAll = squeeze(mdData(1:nTimesteps,1:nChains,1:nCarbons,3));

xBounds = [min(xAll(:)),max(xAll(:))];
yBounds = [min(yAll(:)),max(yAll(:))];
zBounds = [min(zAll(:)),max(zAll(:))];

figure;
hold on;
cmap = turbo(nCarbons);
view(3)

% === Pre-create surface objects ===
s = cell(1, nChains);
for jj = 1:nChains
    s{jj} = surface( ...
        nan(2, nCarbons), nan(2, nCarbons), nan(2, nCarbons), ...
        [1:nCarbons; 1:nCarbons], ...
        'FaceColor', 'none', ...
        'EdgeColor', 'interp', ...
        'LineWidth', .5);
end

xlim(xBounds);
ylim(yBounds);
zlim(zBounds);

colormap(cmap);
clim([1 nCarbons]);
colorbar;
xlabel('X');
ylabel('Y');
zlabel('Z');

% Animation loop
for ii = 1:nTimesteps
    % Get coordinates for this frame
    currentTimestep = squeeze(mdData(ii,:,1:nCarbons,:)); % nChains x nCarbons x 3
    x = squeeze(currentTimestep(:,:,1))';  % nCarbons × nChains
    y = squeeze(currentTimestep(:,:,2))';
    z = squeeze(currentTimestep(:,:,3))';

    % Update each chain's surface data instead of recreating it
    for jj = 1:nChains
        set(s{jj}, ...
            'XData', [x(:,jj)'; x(:,jj)'], ...
            'YData', [y(:,jj)'; y(:,jj)'], ...
            'ZData', [z(:,jj)'; z(:,jj)']);
    end

    % Pause between frames for animation
    if ii ~= nTimesteps
        pause(pauseTimePerTimestep);
    end
end