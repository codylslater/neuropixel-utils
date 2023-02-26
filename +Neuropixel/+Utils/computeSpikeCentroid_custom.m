function image_pos = computeSpikeCentroid_custom(m)
    
image_pos = NaN(length(m.spike_times),2);

    for i = 1:length(m.cluster_centroid)
        [idx,~] = find(m.spike_clusters == i);
        image_pos(idx,1) = m.cluster_centroid(i,1) * ones(length(idx),1);
        image_pos(idx,2) = m.cluster_centroid(i,2) * ones(length(idx),1);
    end
    
end