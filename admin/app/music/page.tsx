"use client";
import Catalog from "@/components/Catalog";
import { Page } from "@/components/ui";

export default function Music() {
  return (
    <Page title="Music for reels" sub="Only upload tracks you have the right to use: your own, licensed, or royalty-free (for example from Pixabay Music or the YouTube Audio Library, following their terms).">
      <Catalog table="music_tracks" title="track" cols={[
        { key: "cover_url", label: "Cover", type: "image", bucket: "music" },
        { key: "id", label: "ID", required: true },
        { key: "title", label: "Title", required: true },
        { key: "artist", label: "Artist", required: true },
        { key: "audio_url", label: "Audio file (MP3 or M4A)", type: "file", bucket: "music", accept: "audio/*", required: true },
        { key: "duration_s", label: "Length (seconds)", type: "number" },
        { key: "bpm", label: "BPM", type: "number", list: false },
        { key: "uses", label: "Reels using it", type: "number", readOnlyOnEdit: true },
        { key: "sort", label: "Order", type: "number" },
        { key: "active", label: "Active", type: "bool" },
      ]} />
    </Page>
  );
}
