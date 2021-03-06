%
% Agent-based model of constrained particle motion on a cylinder
% Authors: Tej Stead, Dhananjay Bhaskar
% Last Modified: Jul 17, 2020
%

close all; clear all;

% seed RNG
rng(5271009);

% number of particles
N = 80;

% simulation params
deltaT = 0.1;
totT = 95;
phi = 1;

% toggle interaction forces
FORCE_ATTR_REPULSION_ON = false;
FORCE_RANDOM_POLARITY_ON = true;
FORCE_CURVATURE_ALIGNMENT_ON = true;

% init positions
X = zeros(N, 3);

% attraction-repulsion params
C_a = 100 * 10;
C_r = 100 * 10;
l_a = 1 * 10;
l_r = 0.3 * 10;
NN_threshold = 25;
USE_NEAREST_NEIGHBORS = false;

% random polarization params
walk_amplitude = 0.1 * 10;
walk_stdev = pi/4;
walk_direction = rand(N, 1) * 2 * pi;
num_repolarization_steps = 10;
num_trailing_positions = 40;

init_repolarization_offset = floor(rand(N, 1) * num_repolarization_steps);

% curvature alignment params
num_neighbors = 1;                  % argument in knnsearch to find closest mesh pt
if(FORCE_CURVATURE_ALIGNMENT_ON)
    num_neighbors = 8;
end

% Supported modes:
% 'gauss-min' - align in direction of minimum Gaussian curvature
% 'gauss-max' - align in direction of maximum Gaussian curvature
% 'gauss-zero' - align in direction of lowest absolute Gaussian curvature
% 'mean-min' - align in direction of minimum mean curvature
% 'mean-max' - align in direction of maximum mean curvature
% 'mean-zero' - align in direction of lowest absolute mean curvature
alignment_mode = 'mean-max';
alignment_magnitude = 0.15 * 10;

% preallocate state variables
P = zeros(N, 3);
PV = zeros(N, 3);
q = [20, 15, 100];
Q = [0.0, 0.0, 0.0];
F = zeros(N, 1);
dFdX = zeros(N, 3);
dFdq = zeros(N, 3);
dXdt = zeros(N, 3);

% preallocate particle trajectories
prev_paths = nan * ones(N, num_trailing_positions, 3);
path_colors = parula(N);

% pick trajectory colors
for i = 1:N
    j = floor(rand() * N) + 1;
    temp = path_colors(j, :);
    path_colors(j, :) = path_colors(i, :);
    path_colors(i, :) = temp;
end

% pick random particle
pt_1_idx = floor(rand()*N) + 1;
pt_2_idx = floor(rand()*N) + 1;
pt_3_idx = floor(rand()*N) + 1;
pt_4_idx = floor(rand()*N) + 1;

% uniform distribution of (Theta, Phi) in [0, 2pi] for initial position
cnt = 0;
a = q(1);
b = q(2);
max_z = q(3);
while cnt < N
    U = rand();
    V = rand();
    Theta = 2*pi*U;
    Z = V * max_z/5 + (max_z * 0.5);
    cnt = cnt + 1;
    X(cnt, :) = [a*cos(Theta), b*sin(Theta), Z];
end

% preload pairwise geodesic distances between mesh points (for static surfaces)
if(isfile("elliptic_cylinder_mesh.mat"))
    load("elliptic_cylinder_mesh.mat");
else
    mesh_theta_num = 80;
    mesh_z_num = 40;
    theta_grid = linspace(0, 2*pi, mesh_theta_num);
    z_grid = linspace(0, max_z, mesh_z_num);
    [Z_mesh_fine, Theta_mesh_fine] = meshgrid(z_grid, theta_grid); 
    mesh_x = a * cos(Theta_mesh_fine);
    mesh_y = b * sin(Theta_mesh_fine);
    mesh_z = Z_mesh_fine;
    mat = adj_mat_elliptic_cylinder(mesh_x, mesh_y, mesh_z);
    [dist_mat, next] = FloydWarshall(mat);
    save elliptic_cylinder_mesh.mat mesh_theta_num mesh_z_num mesh_x mesh_y ...
        Z_mesh_fine Theta_mesh_fine mesh_z mat dist_mat next;
end
dist_range = [0 max(dist_mat(:))];

% preload coarse mesh for visualization
theta_num = 36;
z_num = 18;
theta_grid = linspace(0, 2 * pi, theta_num);
z_grid = linspace(0, max_z, z_num);
[Z_mesh, Theta_mesh] = meshgrid(z_grid, theta_grid); 
vis_x = a * cos(Theta_mesh);
vis_y = b * sin(Theta_mesh);
vis_z = Z_mesh;
    
% compute mean and gaussian curvature
G_curvature = gaussian_curvature_elliptic_cylinder(Theta_mesh_fine, Z_mesh_fine, q);
G_color_limits = [0 max(max(G_curvature))];
M_curvature = mean_curvature_elliptic_cylinder(Theta_mesh_fine, Z_mesh_fine, q);
M_color_limits = [min(min(M_curvature)) max(max(M_curvature))];

% visualize IC
% visualize_surface(X, 0, vis_x, vis_y, vis_z, [-30 30], [-30 30], [-10 120]);
% visualize_geodesic_path(X, 0, [pt_1_idx pt_3_idx], [pt_2_idx pt_4_idx], vis_x, vis_y, vis_z, mesh_x, mesh_y, mesh_z, mesh_z_num, next, [-30 30], [-30 30], [-10 120]);
% visualize_geodesic_heatmap(X, 0, vis_x, vis_y, vis_z, mesh_x, mesh_y, mesh_z, pt_1_idx, [-30 30], [-30 30], [-10 120], dist_range, dist_mat);
visualize_curvature_heatmap(X, 0, vis_x, vis_y, vis_z, mesh_x, mesh_y, mesh_z, [-30 30], [-30 30], [-10 120], M_color_limits, M_curvature, true);
% visualize_trajectories(X, 0, prev_paths, path_colors, vis_x, vis_y, vis_z, [-30 30], [-30 30], [-10 120]);

t = 0;
itr = 0;

while t < totT
    
    % initialize nearest neighbors array
    [indices, dists] = all_mesh_neighbors(X, mesh_x, mesh_y, mesh_z, num_neighbors);

    % compute updated state vectors
    for i = 1 : N

        F(i) = (X(i,1)^2/a^2) + (X(i, 2)^2/b^2) - 1;

        dFdX_i_x = 2*X(i,1)/(a^2);
        dFdX_i_y = 2*X(i,2)/(b^2);
        dFdX_i_z = 0;
        dFdX(i,:) = [dFdX_i_x, dFdX_i_y, dFdX_i_z];
        
        if (FORCE_ATTR_REPULSION_ON) 
            dPdt = 0;
            if(N > 1)
                if(USE_NEAREST_NEIGHBORS)
                    particle_indices = find_neighbors(X, indices, dists, dist_mat, i, NN_threshold);
                else
                    particle_indices = setdiff(1:N, i);    % skip element i 
                end
                sz = numel(particle_indices);
                for j = 1:sz
                    idx = particle_indices(j);
                    diff = X(i, :) - X(idx, :);
                    dist = norm(diff);
                    grad_x = ((C_a * diff(1) * exp(-1 * (dist/l_a)))/(l_a * dist)) ...
                        - ((C_r * diff(1) * exp(-1 * (dist/l_r)))/(l_r * dist));
                    grad_y = ((C_a * diff(2) * exp(-1 * (dist/l_a)))/(l_a * dist)) ...
                        - ((C_r * diff(2) * exp(-1 * (dist/l_r)))/(l_r * dist));
                    grad_z = ((C_a * diff(3) * exp(-1 * (dist/l_a)))/(l_a * dist)) ...
                        - ((C_r * diff(3) * exp(-1 * (dist/l_r)))/(l_r * dist));
                    dPdt = dPdt - (1/sz) * [grad_x grad_y grad_z];
                end
                deltaP = deltaT * dPdt;
                P(i, :) = P(i, :) + deltaP;
            end 
        end
        
        if (FORCE_RANDOM_POLARITY_ON)
            nullspace = [dFdX(i,:); zeros(2,3)];
            assert(numel(nullspace) == 9, "Nullspace computation error.");
            nullspace = null(nullspace);
            nullspace = nullspace';
            if(mod(itr, num_repolarization_steps) == init_repolarization_offset(i))
                temp = rand();
                walk_direction(i) = walk_direction(i) + norminv(temp, 0, walk_stdev);
            end
            deltaP =  cos(walk_direction(i)) * nullspace(1, :) * walk_amplitude;
            deltaP = deltaP + sin(walk_direction(i)) * nullspace(2, :) * walk_amplitude;
            P(i, :) = P(i, :) + deltaP;
        end
        
        if(FORCE_CURVATURE_ALIGNMENT_ON)
            neighbor_indices = indices(i, :);
            switch alignment_mode
                case 'gauss-min'
                    [~, neighbor_idx] = min(G_curvature(neighbor_indices));
                case 'gauss-max'
                    [~, neighbor_idx] = max(G_curvature(neighbor_indices));
                case 'gauss-zero'
                    [~, neighbor_idx] = min(abs(G_curvature(neighbor_indices)));
                case 'mean-min'
                    [~, neighbor_idx] = min(M_curvature(neighbor_indices));
                case 'mean-max'
                    [~, neighbor_idx] = max(M_curvature(neighbor_indices));
                case 'mean-zero'
                    [~, neighbor_idx] = min(abs(M_curvature(neighbor_indices)));
                otherwise
                    error("Invalid curvature alignment mode.");
            end
            neighbor_point_idx = neighbor_indices(neighbor_idx);
            direction = [mesh_x(neighbor_point_idx) mesh_y(neighbor_point_idx) mesh_z(neighbor_point_idx)] - X(i, :);
            direction = direction/norm(direction);
            deltaP = direction * alignment_magnitude;
            P(i, :) = P(i, :) + deltaP;
        end

        dFdq_i_a = -2*X(i,1)^2/(a^3);
        dFdq_i_b = -2*X(i,2)^2/(b^3);
        dFdq_i_z = 0;
        dFdq(i,:) = [dFdq_i_a, dFdq_i_b, dFdq_i_z];

        correction = (dot(dFdX(i,:), P(i,:)) + dot(dFdq(i,:), Q) + phi*F(i))/(norm(dFdX(i,:))^2);
        dXdt(i,:) = P(i,:) - correction*dFdX(i,:);
        
        % store trajectories
        if(itr < num_trailing_positions)
            prev_paths(i, itr + 1, :) = X(i, :);
        else
            prev_paths(i, 1:(num_trailing_positions - 1), :) = prev_paths(i, 2:num_trailing_positions, :);
            prev_paths(i, num_trailing_positions, :) = X(i, :);
        end

    end
    
    % update position
    PV = dXdt;
    for i = 1 : N
        X(i,:) = X(i,:) + deltaT*dXdt(i,:);
    end
    
    P = zeros(N, 3);
    t = t + deltaT;
    itr = itr + 1;
    
    % visualize_surface(X, itr, vis_x, vis_y, vis_z, [-30 30], [-30 30], [-10 120]);
    % visualize_geodesic_path(X, itr, [pt_1_idx pt_3_idx], [pt_2_idx pt_4_idx], vis_x, vis_y, vis_z, mesh_x, mesh_y, mesh_z, mesh_z_num, next, [-30 30], [-30 30], [-10 120]);
    % visualize_geodesic_heatmap(X, itr, vis_x, vis_y, vis_z, mesh_x, mesh_y, mesh_z, pt_1_idx, [-30 30], [-30 30], [-10 120], dist_range, dist_mat);
    visualize_curvature_heatmap(X, itr, vis_x, vis_y, vis_z, mesh_x, mesh_y, mesh_z, [-30 30], [-30 30], [-10 120], M_color_limits, M_curvature, true);
    % visualize_trajectories(X, itr, prev_paths, path_colors, vis_x, vis_y, vis_z, [-30 30], [-30 30], [-10 120]);
    
end

function [adj_mat] = adj_mat_elliptic_cylinder(x, y, z)

    sz = size(x);
    height = sz(1);
    width = sz(2);
    adj_mat = inf*ones(height*width, height*width);
    
    for i = 1:height
        for j = 1:width
            dx = [-1 -1 -1 0 0 0 1 1 1];
            dy = [-1 0 1 -1 0 1 -1 0 1];
            for k = 1:numel(dx)
                new_i = mod(i+dy(k) - 1, height) + 1; 
                new_j = j + dx(k);
                if(new_j < 1 || new_j > width)
                    new_j = j;
                end
                distance = pdist([x(i,j) y(i,j) z(i,j) ; x(new_i, new_j) y(new_i, new_j) z(new_i, new_j)]);
                adj_mat((i-1)*width + j,(new_i - 1)*width + new_j) = distance;
            end
        end
    end
    
end

function [curvature] = gaussian_curvature_elliptic_cylinder(~, ~, ~)

    curvature = 0;

end

function [curvature] = mean_curvature_elliptic_cylinder(Theta_mesh_fine, ~, q)

    a = q(1);
    b = q(2);
    
    num = a * b;
    denom = 2 * (((a^2) * (sin(Theta_mesh_fine).^2)) + ((b^2) * (cos(Theta_mesh_fine).^2))).^(3/2);
    curvature = num./denom;
    
end