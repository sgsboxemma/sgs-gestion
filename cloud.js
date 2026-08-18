(function () {
  "use strict";

  const SUPABASE_URL = "https://ainubvtxdkolggsxebic.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_Jg8fhC6hfcNqeS0oGQF1gQ_4jmds4yO";
  const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
  const BUCKET = "member-files";
  let channel;

  const ext = file => {
    const fromName = (file.name || "").split(".").pop().toLowerCase();
    if (fromName && fromName !== file.name.toLowerCase()) return fromName.replace(/[^a-z0-9]/g, "");
    return file.type === "application/pdf" ? "pdf" : "jpg";
  };

  const normalize = row => ({
    id: row.id,
    last: row.last_name || "",
    first: row.first_name || "",
    sex: row.sex || "",
    birth: row.birth || "",
    phone: row.phone || "",
    email: row.email || "",
    address: row.address || "",
    zip: row.zip || "",
    city: row.city || "",
    catOverride: row.cat_override || "",
    acts: row.acts || [],
    due: Number(row.due || 0),
    payments: row.payments || [],
    comments: row.comments || "",
    photo_path: row.photo_path || "",
    medical_path: row.medical_path || "",
    medical_name: row.medical_name || "",
    photo_url: row.photo_url || "",
    medical_url: row.medical_url || ""
  });

  const record = member => ({
    id: member.id,
    last_name: member.last,
    first_name: member.first,
    sex: member.sex || null,
    birth: member.birth || null,
    phone: member.phone || null,
    email: member.email || null,
    address: member.address || null,
    zip: member.zip || null,
    city: member.city || null,
    cat_override: member.catOverride || null,
    acts: member.acts || [],
    due: Number(member.due || 0),
    payments: member.payments || [],
    comments: member.comments || null,
    photo_path: member.photo_path || null,
    medical_path: member.medical_path || null,
    medical_name: member.medical_name || null,
    updated_at: new Date().toISOString()
  });

  async function signed(path, seconds = 3600) {
    if (!path) return "";
    const { data, error } = await client.storage.from(BUCKET).createSignedUrl(path, seconds);
    if (error) return "";
    return data.signedUrl;
  }

  async function withUrls(member, role) {
    member.photo_url = await signed(member.photo_path);
    if (role !== "coach") member.medical_url = await signed(member.medical_path);
    return member;
  }

  async function upload(memberId, kind, file, limitMb) {
    if (!file) return null;
    if (file.size > limitMb * 1024 * 1024) throw new Error(`${file.name} dépasse ${limitMb} Mo.`);
    if (kind === "photo" && !file.type.startsWith("image/")) throw new Error("La photo doit être une image.");
    if (kind === "medical" && !(file.type.startsWith("image/") || file.type === "application/pdf")) {
      throw new Error("Le certificat doit être une image ou un PDF.");
    }
    const path = `${memberId}/${kind}.${ext(file)}`;
    const { error } = await client.storage.from(BUCKET).upload(path, file, {
      upsert: true,
      contentType: file.type,
      cacheControl: "3600"
    });
    if (error) throw error;
    return path;
  }

  window.CloudStore = {
    async session() {
      const { data } = await client.auth.getSession();
      return data.session;
    },
    async login(email, password) {
      const { data, error } = await client.auth.signInWithPassword({ email, password });
      if (error) throw error;
      return data;
    },
    async logout() {
      await client.auth.signOut();
    },
    async role() {
      const { data: auth } = await client.auth.getUser();
      if (!auth.user) throw new Error("Session expirée.");
      const { data, error } = await client.from("profiles").select("role").eq("user_id", auth.user.id).single();
      if (error || !data) throw new Error("Aucun rôle n’est associé à ce compte.");
      return data.role;
    },
    async loadMembers(role) {
      const { data, error } = await client.rpc("get_members");
      if (error) throw error;
      const rows = Array.isArray(data) ? data : [];
      return Promise.all(rows.map(row => withUrls(normalize(row), role)));
    },
    async saveMember(member, photo, medical) {
      const oldPhoto = member.photo_path;
      const oldMedical = member.medical_path;
      if (photo) member.photo_path = await upload(member.id, "photo", photo, 8);
      if (medical) {
        member.medical_path = await upload(member.id, "medical", medical, 12);
        member.medical_name = medical.name;
      }
      const { error } = await client.from("members").upsert(record(member));
      if (error) {
        member.photo_path = oldPhoto;
        member.medical_path = oldMedical;
        throw error;
      }
    },
    watch() {}
  };
})();
