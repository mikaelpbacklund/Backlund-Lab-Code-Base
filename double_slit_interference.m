% double_slit_interference.m
% Script to generate and plot a double slit interference pattern for multiple wavelengths

% Physical parameters
wavelengths = [450e-9, 532e-9, 635e-9]; % Blue, Green, Red (in meters)
colors = {[0 0 1], [0 0.7 0], [1 0 0]}; % RGB for blue, green, red
labels = {'450 nm (Blue)', '532 nm (Green)', '635 nm (Red)'};
d = 20e-6;           % Distance between slits (20 microns)
a = 5e-6;            % Slit width (5 microns)
L = 1.0;             % Distance to screen (1 meter)
I0 = 1;              % Maximum intensity (arbitrary units)

% Screen setup
y = linspace(-0.2, 0.2, 2000); % Screen positions (meters)

figure;
hold on;
for i = 1:length(wavelengths)
    lambda = wavelengths(i);
    beta = (pi * a * y) / (lambda * L);
    alpha = (pi * d * y) / (lambda * L);
    I = I0 * (cos(alpha)).^2 .* (sinc(beta/pi)).^2;
    plot(y * 1e3, I, 'Color', colors{i}, 'LineWidth', 2, 'DisplayName', labels{i});
end
hold off;
xlabel('Position on screen (mm)');
ylabel('Normalized Intensity');
title('Double Slit Interference Pattern for Multiple Wavelengths');
grid on;
legend('show');

% Calculate and plot the maximum intensity at each point
I_all = zeros(length(wavelengths), length(y));
for i = 1:length(wavelengths)
    lambda = wavelengths(i);
    beta = (pi * a * y) / (lambda * L);
    alpha = (pi * d * y) / (lambda * L);
    I_all(i, :) = I0 * (cos(alpha)).^2 .* (sinc(beta/pi)).^2;
end
[maxI, maxIdx] = max(I_all, [], 1);

figure;
hold on;
% Robustly fill background with color corresponding to max wavelength at each point
N = length(y);
filled = false(1, N);
for i = 1:length(wavelengths)
    mask = (maxIdx == i);
    % Find contiguous regions where this wavelength is max
    start_idx = find(diff([0 mask]) == 1);
    end_idx = find(diff([mask 0]) == -1);
    for k = 1:length(start_idx)
        idx_range = start_idx(k):end_idx(k);
        x_region = y(idx_range) * 1e3;
        y_region = maxI(idx_range);
        fill([x_region, fliplr(x_region)], [zeros(1,length(idx_range)), fliplr(y_region)], colors{i}, 'EdgeColor', 'none', 'FaceAlpha', 0.3);
        filled(idx_range) = true;
    end
end
plot(y * 1e3, maxI, 'k', 'LineWidth', 2);
xlabel('Position on screen (mm)');
ylabel('Maximum Intensity');
title('Maximum Intensity Across All Wavelengths (Colored by Dominant Wavelength)');
grid on;
hold off; 