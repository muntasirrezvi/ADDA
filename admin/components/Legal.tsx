import legal from "@/lib/legal.json";

type Doc = { title: string; intro: string; sections: [string, string][] };

/** Public legal page (no sign-in needed). Text lives in lib/legal.json, shared with the app. */
export default function Legal({ kind }: { kind: "privacy" | "terms" }) {
  const doc = legal[kind] as unknown as Doc;
  return (
    <div className="legal">
      <div className="legal-head">
        <div className="brand">Adda</div>
        <h1>{doc.title}</h1>
        <p className="muted">Last updated {legal.updated}</p>
      </div>
      <p>{doc.intro}</p>
      {doc.sections.map(([h, body]) => (
        <section key={h}>
          <h2>{h}</h2>
          <p>{body}</p>
        </section>
      ))}
      <p className="muted legal-foot">
        <a href={kind === "privacy" ? "../terms/" : "../privacy/"}>{kind === "privacy" ? "Terms of Service" : "Privacy Policy"}</a> · © Adda by Riot
      </p>
    </div>
  );
}
